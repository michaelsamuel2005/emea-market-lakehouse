"""Generate the synthetic market submissions for the EMEA office market lakehouse.

Each market reports in its own template: its own column names and language, area unit, rent
convention, currency, quarter label, date format and number format. The generator writes those
raw files (bronze seeds), the shared reference tables, and an answer key listing every defect it
injected, so the pipeline's tests and reconciliations can be checked against known truth.

Usage:
    python generator/generate.py            # write seeds/bronze, seeds/reference, exercise/madrid, generator/answer_key
    python generator/generate.py --check    # regenerate to a temp folder and verify the committed files are identical

Everything is driven by generator/assumptions.yaml and a fixed random seed, so the output is reproducible.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parent.parent
SQFT_PER_M2 = 1 / 0.09290304  # 10.7639...

# ----------------------------------------------------------------------------------------------
# Local vocabularies: how each market labels things. The pipeline maps these back to shared codes.
# ----------------------------------------------------------------------------------------------
DEAL_TYPE_LOCAL = {
    "en": {"NEW": "New Lease", "REN": "Renewal", "EXP": "Expansion", "SUB": "Sublease", "PRE": "Pre-let"},
    "fr": {"NEW": "Nouveau bail", "REN": "Renouvellement", "EXP": "Extension", "SUB": "Sous-location", "PRE": "BEFA"},
    "de": {"NEW": "Neuvermietung", "REN": "Verlängerung", "EXP": "Erweiterung", "SUB": "Untervermietung", "PRE": "Vorvermietung"},
    "es": {"NEW": "Nuevo contrato", "REN": "Renovación", "EXP": "Ampliación", "SUB": "Subarriendo", "PRE": "Pre-alquiler"},
}
SECTOR_LOCAL = {
    "en": {"FIN": "Banking & Finance", "LEG": "Legal", "PRO": "Professional Services", "TMT": "TMT", "PUB": "Public Sector",
           "INS": "Insurance", "FLX": "Flex Office", "LSC": "Life Sciences", "MFG": "Industrial", "OTH": "Other"},
    "fr": {"FIN": "Banque-Finance", "LEG": "Juridique", "PRO": "Services aux entreprises", "TMT": "Tech-Médias-Télécoms",
           "PUB": "Secteur public", "INS": "Assurance", "FLX": "Espaces flexibles", "LSC": "Santé-Sciences de la vie",
           "MFG": "Industrie", "OTH": "Autre"},
    "de": {"FIN": "Banken/Finanzen", "LEG": "Rechtsberatung", "PRO": "Unternehmensberatung", "TMT": "IT/Medien/Telekommunikation",
           "PUB": "Öffentliche Hand", "INS": "Versicherungen", "FLX": "Flexible Büros", "LSC": "Pharma/Life Sciences",
           "MFG": "Industrie", "OTH": "Sonstige"},
    "es": {"FIN": "Banca y Finanzas", "LEG": "Legal", "PRO": "Servicios profesionales", "TMT": "TMT", "PUB": "Sector público",
           "INS": "Seguros", "FLX": "Flexible", "LSC": "Ciencias de la vida", "MFG": "Industria", "OTH": "Otros"},
}
GRADE_LOCAL = {  # market -> grade code -> local label(s); the first label is the common one
    "LON": {"A": ["Grade A", "Grade A"], "B": ["Grade B"], "C": ["Grade C"]},
    "PAR": {"A": ["Prime", "Neuf ou restructuré"], "B": ["Seconde main récent"], "C": ["Seconde main ancien"]},
    "AMS": {"A": ["A"], "B": ["B"], "C": ["C"]},
    "FRA": {"A": ["Klasse A"], "B": ["Klasse B"], "C": ["Klasse C"]},
    "WAW": {"A": ["A", "A"], "B": ["B", "B+"], "C": ["C"]},
    "MAD": {"A": ["A", "A+"], "B": ["B"], "C": ["C"]},
}
SECTOR_WEIGHTS = {"FIN": 0.18, "LEG": 0.10, "PRO": 0.17, "TMT": 0.17, "PUB": 0.07, "INS": 0.07, "FLX": 0.08,
                  "LSC": 0.04, "MFG": 0.05, "OTH": 0.07}
DEAL_TYPE_WEIGHTS = {"NEW": 0.55, "REN": 0.20, "EXP": 0.10, "SUB": 0.08, "PRE": 0.07}
SEASONAL = {1: 0.90, 2: 1.00, 3: 0.95, 4: 1.15}

# Column layouts per market, per dataset (the raw files' headers)
COLUMNS = {
    "market_stats": {
        "LON": ["Period", "Submarket", "Total_Stock_sq_ft", "Available_Space_sq_ft", "Take_Up_sq_ft", "Prime_Rent_GBP_psf_pa",
                "Prime_Yield", "Completions_sq_ft", "Under_Construction_sq_ft", "Submitted_At"],
        "PAR": ["Trimestre", "Secteur", "Parc_total_m2", "Offre_immediate_m2", "Demande_placee_m2", "Loyer_prime_EUR_m2_an",
                "Taux_prime", "Livraisons_m2", "En_chantier_m2", "Date_envoi"],
        "AMS": ["Quarter", "Submarket", "Stock_m2", "Vacant_m2", "Take_up_m2", "Prime_rent_eur_m2_yr", "Prime_yield_pct",
                "Completions_m2", "Under_construction_m2", "Submitted_at"],
        "FRA": ["Quartal", "Teilmarkt", "Flaechenbestand_m2", "Leerstandsquote_prozent", "Flaechenumsatz_m2",
                "Spitzenmiete_EUR_m2_monat", "Spitzenrendite_prozent", "Fertigstellungen_m2", "Im_Bau_m2", "Gemeldet_am"],
        "WAW": ["period", "submarket", "stock_m2", "vacant_m2", "take_up_m2", "prime_rent_eur_m2_month", "prime_yield",
                "completions_m2", "under_construction_m2", "submitted_at"],
        "MAD": ["Trimestre", "Submercado", "Stock_m2", "Disponibilidad_m2", "Contratacion_m2", "Renta_prime_EUR_m2_mes",
                "Rentabilidad_prime", "Entregas_m2", "En_construccion_m2", "Fecha_envio"],
    },
    "deals": {
        "LON": ["Deal_Ref", "Deal_Date", "Building", "Address", "Submarket", "Tenant", "Sector", "Area_sq_ft", "Rent_GBP_psf_pa",
                "Term_years", "Deal_Type", "Submitted_At"],
        "PAR": ["Ref", "Date_signature", "Immeuble", "Adresse", "Secteur", "Preneur", "Secteur_activite", "Surface_m2",
                "Loyer_facial_EUR_m2_an", "Duree_ferme_ans", "Type_transaction", "Date_envoi"],
        "AMS": ["deal_id", "date", "building", "address", "submarket", "tenant", "sector", "area_m2", "rent_eur_m2_yr",
                "term_years", "deal_type", "submitted_at"],
        "FRA": ["Vorgang", "Datum", "Objekt", "Adresse", "Teilmarkt", "Mieter", "Branche", "Flaeche_m2", "Miete_EUR_m2_monat",
                "Laufzeit_jahre", "Vertragsart", "Gemeldet_am"],
        "WAW": ["deal_id", "date", "building", "address", "submarket", "tenant", "sector", "area_m2", "rent", "rent_currency",
                "rent_basis", "term_years", "deal_type", "submitted_at"],
        "MAD": ["Referencia", "Fecha", "Edificio", "Direccion", "Submercado", "Inquilino", "Sector", "Superficie_m2",
                "Renta_EUR_m2_mes", "Plazo_anos", "Tipo_operacion", "Fecha_envio"],
    },
    "buildings": {
        "LON": ["Building_ID", "Building_Name", "Address", "Postcode", "Submarket", "Grade", "NIA_sq_ft", "Year_Built",
                "Last_Refurbished", "Last_Updated"],
        "PAR": ["Id_immeuble", "Nom", "Adresse", "Code_postal", "Secteur", "Classe", "Surface_utile_m2", "Annee_construction",
                "Annee_renovation", "Mise_a_jour"],
        "AMS": ["building_id", "name", "address", "postcode", "submarket", "grade", "lfa_m2", "year_built", "year_refurbished",
                "last_updated"],
        "FRA": ["Objekt_ID", "Objektname", "Adresse", "PLZ", "Teilmarkt", "Qualitaet", "Mietflaeche_m2", "Baujahr", "Sanierung",
                "Aktualisiert"],
        "WAW": ["building_id", "name", "address", "postcode", "submarket", "class", "gla_m2", "year_built", "year_refurbished",
                "last_updated"],
        "MAD": ["Id_edificio", "Nombre", "Direccion", "CP", "Submercado", "Categoria", "SBA_m2", "Ano_construccion", "Ano_reforma",
                "Actualizado"],
    },
    "availability": {
        "LON": ["Period", "Building_ID", "Available_sq_ft", "Of_Which_Sublet_sq_ft", "Submitted_At"],
        "PAR": ["Trimestre", "Id_immeuble", "Disponible_m2", "Dont_sous_location_m2", "Date_envoi"],
        "AMS": ["quarter", "building_id", "available_m2", "sublease_m2", "submitted_at"],
        "FRA": ["Quartal", "Objekt_ID", "Verfuegbar_m2", "Davon_Untermiete_m2", "Gemeldet_am"],
        "WAW": ["period", "building_id", "available_m2", "sublease_m2", "submitted_at"],
        "MAD": ["Trimestre", "Id_edificio", "Disponible_m2", "Subarriendo_m2", "Fecha_envio"],
    },
}

STREET_WORDS = {
    "LON": (["Bishopsgate", "Fenchurch Street", "Cheapside", "Gresham Street", "Moorgate", "Berkeley Square", "Hanover Square",
             "Oxford Street", "Regent Street", "Kingsway", "High Holborn", "Southwark Street", "Blackfriars Road", "Canada Square",
             "Bank Street", "Cannon Street", "Leadenhall Street", "St James's Square", "Grosvenor Street", "Chancery Lane"],
            ["EC2M", "EC3M", "EC2V", "EC2R", "EC2Y", "W1J", "W1S", "W1D", "W1B", "WC2B", "WC1V", "SE1", "SE1", "E14", "E14",
             "EC4N", "EC3A", "SW1Y", "W1K", "WC2A"]),
    "PAR": (["avenue des Champs-Élysées", "rue de la Paix", "boulevard Haussmann", "avenue Hoche", "rue Saint-Honoré",
             "place de la Défense", "cours Valmy", "esplanade du Général de Gaulle", "rue de Courcelles", "avenue de Wagram",
             "rue de Vaugirard", "avenue d'Italie", "boulevard du Montparnasse", "rue du Faubourg Saint-Antoine", "avenue de France",
             "avenue Charles de Gaulle", "rue de Villiers", "avenue du Président Wilson", "boulevard de Stalingrad", "rue Michelet"],
            ["75008", "75002", "75009", "75008", "75001", "92400", "92800", "92400", "75017", "75017", "75015", "75013", "75014",
             "75012", "75013", "92200", "92300", "92800", "92240", "92110"]),
    "AMS": (["Gustav Mahlerlaan", "Zuidplein", "Claude Debussylaan", "Strawinskylaan", "Herengracht", "Keizersgracht", "Rokin",
             "Vijzelstraat", "Hoogoorddreef", "Paasheuvelweg", "Bijlmerdreef", "Hullenbergweg", "Radarweg", "Basisweg", "Naritaweg",
             "Teleportboulevard"],
            ["1082", "1077", "1082", "1077", "1017", "1015", "1012", "1017", "1101", "1105", "1102", "1101", "1043", "1043", "1043",
             "1043"]),
    "FRA": (["Neue Mainzer Straße", "Taunustor", "Junghofstraße", "Mainzer Landstraße", "Bockenheimer Landstraße", "Westendstraße",
             "Taunusanlage", "Zeil", "Große Eschenheimer Straße", "Kaiserstraße", "Mergenthalerallee", "Frankfurter Straße",
             "Düsseldorfer Straße", "Lyoner Straße", "Herriotstraße", "Hahnstraße"],
            ["60311", "60310", "60311", "60325", "60323", "60325", "60329", "60313", "60313", "60329", "65760", "65760", "65760",
             "60528", "60528", "60528"]),
    "WAW": (["ul. Emilii Plater", "rondo ONZ", "ul. Złota", "al. Jana Pawła II", "ul. Grzybowska", "ul. Prosta", "ul. Towarowa",
             "ul. Domaniewska", "ul. Postępu", "ul. Marynarska", "ul. Wołoska", "ul. Kasprzaka", "ul. Przyokopowa", "ul. Słomińskiego",
             "ul. Rydygiera", "al. Jerozolimskie"],
            ["00-125", "00-124", "00-120", "00-867", "00-844", "00-838", "00-811", "02-672", "02-676", "02-674", "02-675", "01-224",
             "01-208", "00-195", "01-793", "00-508"]),
    "MAD": (["Paseo de la Castellana", "calle de Alcalá", "calle de Serrano", "calle de Velázquez", "calle de Goya", "calle de Orense",
             "avenida de Burgos", "calle de Julián Camarillo", "calle de Alcalá", "avenida de Manoteras", "calle de Albarracín",
             "avenida de Europa", "calle de la Ribera del Loira", "paseo de la Habana", "calle de Josefa Valcárcel", "avenida de Aragón"],
            ["28046", "28014", "28001", "28001", "28001", "28020", "28036", "28037", "28027", "28050", "28037", "28224", "28042",
             "28036", "28027", "28022"]),
}

BUILDING_WORDS = ["House", "Tower", "Court", "Place", "Gate", "Plaza", "Point", "Centre", "Square", "Building", "Park", "Quay"]
TENANT_STEMS = ["Northgate", "Helix", "Meridian", "Larkspur", "Cobalt", "Ashcombe", "Veridian", "Quill", "Halden", "Orbis", "Tamar",
                "Brightwater", "Kestrel", "Linden", "Sable", "Pinnacle", "Harrow", "Aldwyn", "Fenwick", "Calder", "Osprey", "Marlow",
                "Ridgeway", "Ember", "Sterling", "Beacon", "Wren", "Granite", "Juniper", "Vantage", "Elmgrove", "Thorne", "Ravel",
                "Corvid", "Lumen", "Atlas", "Nimbus", "Arden", "Solace", "Tern"]
TENANT_SUFFIX = {"FIN": ["Capital", "Asset Management", "Securities", "Bank", "Partners"],
                 "LEG": ["LLP", "Avocats", "Rechtsanwälte", "Abogados", "Legal"],
                 "PRO": ["Consulting", "Advisory", "Associates", "Group", "Partners"],
                 "TMT": ["Technologies", "Software", "Digital", "Media", "Labs"],
                 "PUB": ["Agency", "Authority", "Institute", "Council", "Office"],
                 "INS": ["Insurance", "Assurance", "Re", "Underwriting", "Mutual"],
                 "FLX": ["Workspace", "Flex", "Hub", "Spaces", "Offices"],
                 "LSC": ["Biosciences", "Pharma", "Health", "Therapeutics", "Diagnostics"],
                 "MFG": ["Industries", "Engineering", "Systems", "Materials", "Energy"],
                 "OTH": ["Holdings", "Foundation", "Retail", "Logistics", "Services"]}
GLOBAL_TENANTS = [("Meridian Capital", "FIN"), ("Northgate LLP", "LEG"), ("Helix Technologies", "TMT"), ("Cobalt Advisory", "PRO"),
                  ("Orbis Insurance", "INS"), ("Lumen Workspace", "FLX"), ("Atlas Pharma", "LSC"), ("Sterling Bank", "FIN")]


@dataclass
class Market:
    id: str
    cfg: dict
    submarkets: list = field(default_factory=list)
    buildings: list = field(default_factory=list)
    tenants: list = field(default_factory=list)


# ----------------------------------------------------------------------------------------------
# Formatting helpers: numbers, periods and dates in each market's convention
# ----------------------------------------------------------------------------------------------
def fmt_number(x: float, style: str, decimals: int = 0) -> str:
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return ""
    if style == "point":        # 1,234,567.50
        return f"{x:,.{decimals}f}"
    if style == "plain":        # 1234567.5
        return f"{x:.{decimals}f}"
    if style == "fr":           # 1 234 567,50
        return f"{x:,.{decimals}f}".replace(",", " ").replace(".", ",")
    if style == "de":           # 1.234.567,50
        return f"{x:,.{decimals}f}".replace(",", "§").replace(".", ",").replace("§", ".")
    raise ValueError(style)


def fmt_period(year: int, q: int, style: str) -> str:
    return {"uk": f"Q{q} {year}", "fr": f"T{q} {year}", "iso_q": f"{year}-Q{q}", "de": f"{q}. Quartal {year}",
            "compact": f"{year}Q{q}", "es": f"{q}T {year}"}[style]


def fmt_date(d: date, style: str) -> str:
    return {"dmy_slash": d.strftime("%d/%m/%Y"), "dmy_dot": d.strftime("%d.%m.%Y"), "iso": d.isoformat()}[style]


def fmt_yield(y: float, market_id: str) -> str:
    # Each market writes its yield differently; the pipeline must normalise all of them to a fraction.
    return {"LON": f"{y*100:.2f}%", "PAR": f"{y*100:.2f} %".replace(".", ","), "AMS": f"{y*100:.2f}", "FRA": f"{y*100:.2f}".replace(".", ","),
            "WAW": f"{y:.4f}", "MAD": f"{y*100:.1f} %".replace(".", ",")}[market_id]


def quarter_end(year: int, q: int) -> date:
    m = q * 3
    nxt = date(year + (m == 12), (m % 12) + 1, 1)
    return nxt - timedelta(days=1)


def quarter_start(year: int, q: int) -> date:
    return date(year, (q - 1) * 3 + 1, 1)


def area_out(m2: float, unit: str) -> float:
    return m2 * SQFT_PER_M2 if unit == "sqft" else m2


# ----------------------------------------------------------------------------------------------
# Generation
# ----------------------------------------------------------------------------------------------
class Generator:
    def __init__(self, assumptions: dict):
        self.a = assumptions
        self.rng = np.random.default_rng(assumptions["seed"])
        fy, fq = int(assumptions["quarters"]["first"][:4]), int(assumptions["quarters"]["first"][-1])
        ly, lq = int(assumptions["quarters"]["last"][:4]), int(assumptions["quarters"]["last"][-1])
        self.quarters: list[tuple[int, int]] = []
        y, q = fy, fq
        while (y, q) <= (ly, lq):
            self.quarters.append((y, q))
            q += 1
            if q == 5:
                y, q = y + 1, 1
        self.answer_key: list[dict] = []
        self.markets: dict[str, Market] = {}
        self.fx = self._fx_table()

    # -- reference ------------------------------------------------------------------------------
    def _fx_table(self) -> dict[tuple[str, str], float]:
        out = {}
        n = len(self.quarters) - 1
        for ccy, span in self.a["fx"].items():
            for i, (y, q) in enumerate(self.quarters):
                base = span["start"] + (span["end"] - span["start"]) * (i / n)
                noise = 0 if ccy == "EUR" else float(self.rng.normal(0, 0.006)) * base
                out[(f"{y}Q{q}", ccy)] = round(base + noise, 4)
        return out

    def log(self, market: str, dataset: str, key: str, defect: str, detail: str):
        self.answer_key.append({"market_id": market, "dataset": dataset, "row_key": key, "defect_type": defect, "detail": detail})

    # -- buildings ------------------------------------------------------------------------------
    def make_buildings(self, m: Market):
        streets, postcodes = STREET_WORDS[m.id]
        n_per_sub = 30
        bid = 1
        used_names: set[str] = set()
        for sm in m.submarkets:
            for _ in range(n_per_sub):
                size = float(np.exp(self.rng.normal(np.log(11000), 0.55)))
                size = max(1500.0, min(size, 90000.0))
                grade = self.rng.choice(["A", "B", "C"], p=[0.45, 0.4, 0.15])
                year_built = int(self.rng.integers(1960, 2024))
                refurb = int(self.rng.integers(max(year_built + 5, 2005), 2026)) if (self.rng.random() < 0.5 and year_built < 2015) else None
                while True:  # building names are unique within a market, so deals can be matched to the register by name
                    i = int(self.rng.integers(0, len(streets)))
                    num = int(self.rng.integers(1, 180))
                    name = f"{num} {streets[i]}" if self.rng.random() < 0.55 else f"{self.rng.choice(TENANT_STEMS)} {self.rng.choice(BUILDING_WORDS)}"
                    if name not in used_names:
                        used_names.add(name)
                        break
                m.buildings.append({
                    "id": f"{m.id}-B{bid:04d}", "name": name, "address": f"{num} {streets[i]}", "postcode": postcodes[i],
                    "submarket": sm, "grade": grade, "area_m2": round(size, 0), "year_built": year_built, "refurb": refurb,
                    "last_updated": date(2026, 1, 15) + timedelta(days=int(self.rng.integers(0, 200))),
                })
                bid += 1

    # -- tenants --------------------------------------------------------------------------------
    def make_tenants(self, m: Market):
        sectors = list(SECTOR_WEIGHTS)
        probs = np.array(list(SECTOR_WEIGHTS.values()))
        stems = list(self.rng.permutation(TENANT_STEMS))
        for i in range(60):
            sec = str(self.rng.choice(sectors, p=probs))
            name = f"{stems[i % len(stems)]} {self.rng.choice(TENANT_SUFFIX[sec])}"
            if i >= len(stems):
                name = f"{name} {m.cfg['name']}"
            m.tenants.append((name, sec))
        for name, sec in GLOBAL_TENANTS:  # the same occupiers appear in several markets
            m.tenants.append((name, sec))

    # -- market stats + availability + deals -------------------------------------------------
    def make_market(self, mid: str) -> dict[str, list[dict]]:
        cfg = self.a["markets"][mid]
        m = Market(mid, cfg, submarkets=cfg["submarkets"])
        self.markets[mid] = m
        self.make_buildings(m)
        self.make_tenants(m)
        n_q = len(self.quarters)
        stats_rows, avail_rows, deal_rows = [], [], []
        truth_rows = []  # the clean numbers, for the answer key
        deal_seq = 1
        mismatch_q = self.rng.integers(3, n_q - 1) if mid == "WAW" else None  # the one market-quarter whose reported vacancy is off
        for sm in m.submarkets:
            stock = float(sm["stock_m2"])
            vac = float(sm["vacancy"])
            for i, (y, q) in enumerate(self.quarters):
                t_back = (n_q - 1 - i) / 4.0  # years before the last quarter
                completions = stock * 0.004 if self.rng.random() < 0.3 else 0.0
                stock += completions
                vac = min(0.35, max(0.015, vac + float(self.rng.normal(0, 0.004))))
                vacant = stock * vac
                take_up = sm["take_up_m2"] * SEASONAL[q] * float(np.exp(self.rng.normal(0, 0.12)))
                prime_rent = sm["prime_rent"] / ((1 + sm["rent_growth"]) ** t_back) * float(np.exp(self.rng.normal(0, 0.01)))
                yld = sm["yield"] + (0.004 if i < 6 else 0.0) + float(self.rng.normal(0, 0.0008))
                under_con = stock * float(self.rng.uniform(0.015, 0.04))
                submitted = datetime.combine(quarter_end(y, q), datetime.min.time()) + timedelta(days=int(self.rng.integers(12, 25)), hours=9)
                reported_vac_rate = vac
                if mismatch_q is not None and i == mismatch_q and sm is m.submarkets[0]:
                    reported_vac_rate = vac + 0.045  # the known reconciliation defect
                    self.log(mid, "market_stats", f"{y}Q{q}|{sm['id']}", "vacancy_mismatch",
                             f"reported vacancy {reported_vac_rate:.3f} vs building register {vac:.3f} (+4.5pp)")
                truth_rows.append({"market_id": mid, "submarket_id": sm["id"], "quarter_id": f"{y}Q{q}", "stock_m2": round(stock),
                                   "vacant_m2": round(stock * reported_vac_rate), "vacancy_rate": round(reported_vac_rate, 4),
                                   "take_up_m2": round(take_up), "prime_rent_local": round(prime_rent, 2), "prime_yield": round(yld, 4),
                                   "completions_m2": round(completions), "under_construction_m2": round(under_con)})
                stats_rows.append(self._stats_row(m, sm, y, q, stock, reported_vac_rate, take_up, prime_rent, yld, completions, under_con, submitted))
                # bottom-up availability across the submarket's tracked buildings, matching the TRUE vacancy rate
                avail_rows.extend(self._availability_rows(m, sm, y, q, vac, submitted))
                # deals summing to take-up
                deal_rows.extend(self._deal_rows(m, sm, y, q, take_up, prime_rent, submitted, deal_seq))
                deal_seq += 1000
        # resubmitted market-quarters: a later copy with slightly different numbers; the later one must win
        for _ in range(self.a["defects"]["market_stats"]["resubmitted_quarters"] if mid in ("LON", "PAR") else 0):
            r = stats_rows[int(self.rng.integers(0, len(stats_rows)))]
            dup = dict(r)
            c = COLUMNS["market_stats"][mid]
            dup[c[9]] = (datetime.fromisoformat(r[c[9]]) + timedelta(days=16)).isoformat(sep=" ")
            dup["_truth_take_up"] = r["_truth_take_up"] * 1.03
            dup[c[4]] = fmt_number(area_out(dup["_truth_take_up"], cfg["area_unit"]), cfg["number_format"])
            stats_rows.append(dup)
            self.log(mid, "market_stats", f"{r[c[0]]}|{r[c[1]]}", "resubmitted_quarter", "two submissions; the later one (+16 days) is the valid one")
        self._inject_deal_defects(m, deal_rows)
        bld_rows = self._building_rows(m)
        return {"market_stats": stats_rows, "availability": avail_rows, "deals": deal_rows, "buildings": bld_rows, "truth": truth_rows}

    def _stats_row(self, m, sm, y, q, stock, vac_rate, take_up, prime_rent, yld, completions, under_con, submitted) -> dict:
        cfg, mid = m.cfg, m.id
        c = COLUMNS["market_stats"][mid]
        nf, au = cfg["number_format"], cfg["area_unit"]
        row = {c[0]: fmt_period(y, q, cfg["period_format"]), c[1]: sm["local_name"], c[2]: fmt_number(area_out(stock, au), nf)}
        if cfg.get("vacancy_reported_as") == "rate":
            row[c[3]] = fmt_number(vac_rate * 100, nf, 1)
        else:
            row[c[3]] = fmt_number(area_out(stock * vac_rate, au), nf)
        row[c[4]] = fmt_number(area_out(take_up, au), nf)
        row[c[5]] = fmt_number(prime_rent, nf, 2)
        row[c[6]] = fmt_yield(yld, mid)
        row[c[7]] = fmt_number(area_out(completions, au), nf)
        row[c[8]] = fmt_number(area_out(under_con, au), nf)
        row[c[9]] = submitted.isoformat(sep=" ")
        row["_truth_take_up"] = take_up
        return row

    def _availability_rows(self, m, sm, y, q, vac_rate, submitted) -> list[dict]:
        cfg, mid = m.cfg, m.id
        c = COLUMNS["availability"][mid]
        blds = [b for b in m.buildings if b["submarket"] is sm]
        total = sum(b["area_m2"] for b in blds)
        target = total * vac_rate * float(np.exp(self.rng.normal(0, 0.03)))
        # spread the vacancy over an uneven subset of buildings so the register adds up to the true
        # vacancy (within the 3% noise above): capped at 90% of a building, remainder redistributed
        weights = self.rng.dirichlet(np.ones(len(blds)) * 0.35)
        caps = np.array([b["area_m2"] * 0.9 for b in blds])
        alloc = np.minimum(caps, target * weights)
        for _ in range(6):
            remainder = target - alloc.sum()
            room = caps - alloc
            if remainder < 1 or room.sum() < 1:
                break
            share = room / room.sum()
            alloc = np.minimum(caps, alloc + remainder * share)
        rows = []
        for b, avail in zip(blds, alloc):
            avail = float(avail)
            if avail < 150:
                continue
            sub = avail * float(self.rng.choice([0, 0, 0, 0.3, 0.6]))
            rows.append({c[0]: fmt_period(y, q, cfg["period_format"]), c[1]: b["id"],
                         c[2]: fmt_number(area_out(avail, cfg["area_unit"]), cfg["number_format"]),
                         c[3]: fmt_number(area_out(sub, cfg["area_unit"]), cfg["number_format"]),
                         c[4]: submitted.isoformat(sep=" ")})
        return rows

    def _deal_rows(self, m, sm, y, q, take_up, prime_rent, submitted, seq0) -> list[dict]:
        cfg, mid = m.cfg, m.id
        c = COLUMNS["deals"][mid]
        lang = cfg["deals_language"]
        blds = [b for b in m.buildings if b["submarket"] is sm]
        rows, total, seq = [], 0.0, seq0
        qs, qe = quarter_start(y, q), quarter_end(y, q)
        while total < take_up * 0.97:
            size = float(np.exp(self.rng.normal(np.log(cfg["avg_deal_m2"]), 0.7)))
            size = max(150.0, min(size, 40000.0))
            if total + size > take_up * 1.03:
                size = max(150.0, take_up - total)
                if size < 150:
                    break
            total += size
            fitting = [b for b in blds if b["area_m2"] >= size]  # a deal cannot be larger than its building
            if not fitting:
                fitting = sorted(blds, key=lambda b: -b["area_m2"])[:3]
                size = min(size, fitting[0]["area_m2"])
            b = fitting[int(self.rng.integers(0, len(fitting)))]
            tenant, sec = m.tenants[int(self.rng.integers(0, len(m.tenants)))]
            dtype = str(self.rng.choice(list(DEAL_TYPE_WEIGHTS), p=list(DEAL_TYPE_WEIGHTS.values())))
            grade_factor = {"A": 0.95, "B": 0.78, "C": 0.62}[b["grade"]]
            rent = prime_rent * grade_factor * float(np.exp(self.rng.normal(0, 0.08)))
            if dtype == "SUB":
                rent *= 0.85
            d = qs + timedelta(days=int(self.rng.integers(0, (qe - qs).days + 1)))
            term = int(self.rng.choice([3, 5, 5, 6, 9, 10, 10, 12, 15]))
            ref = f"{mid}-{y}{q}-{seq:05d}"
            row = {c[0]: ref, c[1]: fmt_date(d, cfg["date_format"]), c[2]: b["name"], c[3]: f"{b['address']}, {b['postcode']}",
                   c[4]: sm["local_name"], c[5]: tenant, c[6]: SECTOR_LOCAL[lang][sec],
                   c[7]: fmt_number(area_out(size, cfg["area_unit"]), cfg["number_format"])}
            rent_str = fmt_number(rent, cfg["number_format"], 2)
            if mid == "WAW":
                ccy = "EUR"
                if self.rng.random() < cfg["pln_deal_share"]:
                    ccy = "PLN"
                    rent_str = fmt_number(rent * self.fx[(f"{y}Q{q}", "PLN")], cfg["number_format"], 2)
                row[c[8]], row[c[9]], row[c[10]] = rent_str, ccy, "per m2 per month"
                row[c[11]], row[c[12]], row[c[13]] = str(term), DEAL_TYPE_LOCAL[lang][dtype], submitted.isoformat(sep=" ")
            else:
                row[c[8]], row[c[9]], row[c[10]], row[c[11]] = rent_str, str(term), DEAL_TYPE_LOCAL[lang][dtype], submitted.isoformat(sep=" ")
            row["_truth"] = {"area_m2": round(size, 1), "rent_local": round(rent, 2), "building_id": b["id"], "sector": sec,
                             "deal_type": dtype, "date": d.isoformat(), "tenant": tenant, "submarket_id": sm["id"]}
            rows.append(row)
            seq += 1
        return rows

    def _inject_deal_defects(self, m: Market, rows: list[dict]):
        cfg, mid = m.cfg, m.id
        c = COLUMNS["deals"][mid]
        d = self.a["defects"]["deals"]
        n = len(rows)
        rent_col = c[8]
        area_col = c[7]
        idx = self.rng.permutation(n)
        k = 0

        def take(share):
            nonlocal k
            cnt = int(round(n * share))
            out = [rows[j] for j in idx[k:k + cnt]]
            k += cnt
            return out

        for r in take(d["confidential_rent_share"]):
            r[rent_col] = ""
            self.log(mid, "deals", r[c[0]], "confidential_rent", "rent withheld by the market (allowed; not an error)")
        for r in take(d["missing_submarket_share"]):
            r[c[4]] = ""
            self.log(mid, "deals", r[c[0]], "missing_submarket", "submarket blank; derivable from the building register")
        for r in take(d["wrong_rent_unit_share"]):
            if r[rent_col]:
                factor = 12 if cfg["rent_unit"] == "per_m2_month" else (1 / 12)
                r[rent_col] = fmt_number(r["_truth"]["rent_local"] * factor, cfg["number_format"], 2)
                self.log(mid, "deals", r[c[0]], "wrong_rent_unit", f"rent entered x{factor:.3g} (annual vs monthly mix-up)")
        for r in take(d["wrong_area_unit_share"]):
            if cfg["area_unit"] == "sqft":
                r[area_col] = fmt_number(r["_truth"]["area_m2"], cfg["number_format"])
                self.log(mid, "deals", r[c[0]], "wrong_area_unit", "area entered in m2 in a sq ft file (10.76x too small)")
            else:
                r[area_col] = fmt_number(r["_truth"]["area_m2"] * SQFT_PER_M2, cfg["number_format"])
                self.log(mid, "deals", r[c[0]], "wrong_area_unit", "area entered in sq ft in a m2 file (10.76x too large)")
        for r in take(d["future_date_share"]):
            dd = date.fromisoformat(r["_truth"]["date"])
            r[c[1]] = fmt_date(dd.replace(year=dd.year + 10), cfg["date_format"])
            self.log(mid, "deals", r[c[0]], "future_date", "year typed ten years ahead")
        dups = []
        for r in take(d["exact_duplicate_share"]):
            dup = dict(r)
            dup["_truth"] = dict(r["_truth"])
            dup[c[-1]] = (datetime.fromisoformat(r[c[-1]]) + timedelta(days=9)).isoformat(sep=" ")
            dups.append(dup)
            self.log(mid, "deals", r[c[0]], "exact_duplicate", "the same deal resubmitted nine days later")
        for r in take(d["near_duplicate_share"]):
            dup = dict(r)
            dup["_truth"] = dict(r["_truth"])
            dup[c[0]] = r[c[0]] + "R"
            dup[c[5]] = r[c[5]].upper() if self.rng.random() < 0.5 else r[c[5]] + " Ltd"
            dup[c[-1]] = (datetime.fromisoformat(r[c[-1]]) + timedelta(days=20)).isoformat(sep=" ")
            dups.append(dup)
            self.log(mid, "deals", dup[c[0]], "near_duplicate", f"duplicate of {r[c[0]]} with the tenant name spelt differently")
        rows.extend(dups)
        # casing/whitespace noise in coded fields: a small share, no answer-key entry (the mapping must simply cope)
        dt_col = c[12] if mid == "WAW" else c[10]
        for r in rows:
            if self.rng.random() < 0.04:
                r[dt_col] = r[dt_col].lower() if self.rng.random() < 0.5 else r[dt_col] + " "
        self.rng.shuffle(rows)

    def _building_rows(self, m: Market) -> list[dict]:
        cfg, mid = m.cfg, m.id
        c = COLUMNS["buildings"][mid]
        rows = []
        for b in m.buildings:
            labels = GRADE_LOCAL[mid][b["grade"]]
            grade = labels[int(self.rng.integers(0, len(labels)))]
            if self.rng.random() < self.a["defects"]["buildings"]["missing_grade_share"]:
                grade = ""
                self.log(mid, "buildings", b["id"], "missing_grade", "grade blank")
            rows.append({c[0]: b["id"], c[1]: b["name"], c[2]: b["address"], c[3]: b["postcode"], c[4]: b["submarket"]["local_name"],
                         c[5]: grade, c[6]: fmt_number(area_out(b["area_m2"], cfg["area_unit"]), cfg["number_format"]),
                         c[7]: str(b["year_built"]), c[8]: str(b["refurb"]) if b["refurb"] else "",
                         c[9]: fmt_date(b["last_updated"], cfg["date_format"])})
        # refurbished resubmissions: the building sent again with a later date and a better grade (latest row wins)
        for j in self.rng.choice(len(rows), self.a["defects"]["buildings"]["refurbished_resubmissions"], replace=False):
            r = dict(rows[int(j)])
            r[c[5]] = GRADE_LOCAL[mid]["A"][0]
            r[c[8]] = "2026"
            r[c[9]] = fmt_date(date(2026, 9, 1) + timedelta(days=int(self.rng.integers(0, 40))), cfg["date_format"])
            rows.append(r)
            self.log(mid, "buildings", r[c[0]], "resubmitted_building", "sent twice; the later row (refurbished to Grade A) is current")
        return rows

    # -- reference tables -----------------------------------------------------------------------
    def reference_tables(self, modelled: list[str]) -> dict[str, list[dict]]:
        a = self.a
        markets = [{"market_id": mid, "market_name": c["name"], "country_code": c["country"],
                    "country_name": {"GB": "United Kingdom", "FR": "France", "NL": "Netherlands", "DE": "Germany", "PL": "Poland", "ES": "Spain"}[c["country"]],
                    "currency_code": c["currency"], "area_unit": c["area_unit"], "rent_unit": c["rent_unit"],
                    "region": "CEE" if c["country"] == "PL" else "Western Europe",
                    "timezone": {"GB": "Europe/London", "FR": "Europe/Paris", "NL": "Europe/Amsterdam", "DE": "Europe/Berlin", "PL": "Europe/Warsaw", "ES": "Europe/Madrid"}[c["country"]]}
                   for mid, c in a["markets"].items() if mid in modelled]
        submarkets = [{"market_id": mid, "submarket_id": s["id"], "submarket_name": s["name"], "local_name": s["local_name"]}
                      for mid, c in a["markets"].items() if mid in modelled for s in c["submarkets"]]
        fx = [{"quarter_id": qid, "currency_code": ccy, "units_per_eur": rate, "rate_date": quarter_end(int(qid[:4]), int(qid[-1])).isoformat()}
              for (qid, ccy), rate in sorted(self.fx.items())]
        grade_map, deal_map, sector_map = [], [], []
        for mid in modelled:
            lang = a["markets"][mid]["deals_language"]
            for code, labels in GRADE_LOCAL[mid].items():
                for lab in dict.fromkeys(labels):
                    grade_map.append({"market_id": mid, "local_grade": lab, "grade_code": code})
            for code, lab in DEAL_TYPE_LOCAL[lang].items():
                deal_map.append({"market_id": mid, "local_deal_type": lab, "deal_type_code": code})
            for code, lab in SECTOR_LOCAL[lang].items():
                sector_map.append({"market_id": mid, "local_sector": lab, "sector_code": code})
        sectors = [{"sector_code": s["code"], "sector_name": s["name"]} for s in a["sectors"]]
        deal_types = [{"deal_type_code": d["code"], "deal_type_name": d["name"]} for d in a["deal_types"]]
        grades = [{"grade_code": g["code"], "grade_name": g["name"]} for g in a["grades"]]
        return {"ref_markets": markets, "ref_submarkets": submarkets, "ref_fx_rates": fx, "ref_grade_mapping": grade_map,
                "ref_deal_type_mapping": deal_map, "ref_sector_mapping": sector_map, "ref_sectors": sectors,
                "ref_deal_types": deal_types, "ref_grades": grades}


# ----------------------------------------------------------------------------------------------
# Writing
# ----------------------------------------------------------------------------------------------
def write_csv(path: Path, rows: list[dict], columns: list[str]):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


CORE_MARKETS = ("LON", "PAR", "AMS", "FRA", "WAW")
EXERCISE_MARKETS = ("MAD",)


def onboarded_markets() -> tuple[str, ...]:
    """The five core markets, plus an exercise market once it has been onboarded (configured under
    vars.markets in dbt_project.yml). After onboarding, Madrid's raw files, reference rows and answer-key
    rows are part of the project, and --check expects them there."""
    project = yaml.safe_load((ROOT / "dbt_project.yml").read_text(encoding="utf-8"))
    configured = set(project["vars"]["markets"])
    return CORE_MARKETS + tuple(m for m in EXERCISE_MARKETS if m in configured)


def generate(out_root: Path, modelled=None, exercise=EXERCISE_MARKETS) -> dict:
    assumptions = yaml.safe_load((ROOT / "generator" / "assumptions.yaml").read_text(encoding="utf-8"))
    modelled = tuple(modelled) if modelled is not None else onboarded_markets()
    g = Generator(assumptions)
    summary = {}
    for mid in list(modelled) + [m for m in exercise if m not in modelled]:   # same order, same random draws
        data = g.make_market(mid)
        folders = []
        if mid in modelled:
            folders.append(out_root / "seeds" / "bronze")
        if mid in exercise:
            folders.append(out_root / "exercise" / assumptions["markets"][mid]["name"].lower() / "raw")
        for folder in folders:
            for ds in ("market_stats", "deals", "buildings", "availability"):
                write_csv(folder / f"{mid.lower()}_{ds}.csv", data[ds], COLUMNS[ds][mid])
        write_csv(out_root / "generator" / "answer_key" / f"truth_market_stats_{mid.lower()}.csv", data["truth"], list(data["truth"][0]))
        truth_deals = [{"deal_ref": r[COLUMNS["deals"][mid][0]], **r["_truth"]} for r in data["deals"]]
        write_csv(out_root / "generator" / "answer_key" / f"truth_deals_{mid.lower()}.csv", truth_deals, list(truth_deals[0]))
        summary[mid] = {ds: len(data[ds]) for ds in ("market_stats", "deals", "buildings", "availability")}
    refs = g.reference_tables(list(modelled))
    for name, rows in refs.items():
        write_csv(out_root / "seeds" / "reference" / f"{name}.csv", rows, list(rows[0]))
    for mid in exercise:  # the rows the exercise market will need appending to the reference seeds
        ex_refs = g.reference_tables([mid])
        for name in ("ref_markets", "ref_submarkets", "ref_grade_mapping", "ref_deal_type_mapping", "ref_sector_mapping"):
            rows = ex_refs[name]
            write_csv(out_root / "exercise" / assumptions["markets"][mid]["name"].lower() / "reference" / f"{name}_rows.csv", rows, list(rows[0]))
    cols = ["market_id", "dataset", "row_key", "defect_type", "detail"]
    write_csv(out_root / "generator" / "answer_key" / "defects.csv", g.answer_key, cols)
    # the same answer key as a seed, so the pipeline can score its own detection rate (ops.ops_defect_detection)
    write_csv(out_root / "seeds" / "answer_key" / "answer_key_defects.csv", [r for r in g.answer_key if r["market_id"] in modelled], cols)
    summary["defects"] = len(g.answer_key)
    return summary


def folder_hash(root: Path, rel_dirs) -> dict[str, str]:
    out = {}
    for rel in rel_dirs:
        for p in sorted((root / rel).rglob("*.csv")):
            out[str(p.relative_to(root))] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="regenerate into a temp folder and verify the committed CSVs match")
    args = ap.parse_args()
    dirs = ["seeds/bronze", "seeds/reference", "seeds/answer_key", "exercise", "generator/answer_key"]
    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            generate(tmp)
            fresh, committed = folder_hash(tmp, dirs), folder_hash(ROOT, dirs)
            committed = {k: committed.get(k) for k in fresh}  # hand-written files in the same folders are not compared
            if fresh != committed:
                diff = sorted(k for k in fresh if fresh[k] != committed[k])
                print("MISMATCH:", *diff, sep="\n  ")
                sys.exit(1)
            print(f"OK: {len(fresh)} generated files match the committed ones")
        return
    for d in dirs:
        shutil.rmtree(ROOT / d, ignore_errors=True)
    summary = generate(ROOT)
    for mid, counts in summary.items():
        print(mid, counts)


if __name__ == "__main__":
    main()
