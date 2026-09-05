INSERT INTO instrument_identity_alias
    (exchange, current_symbol, alias_symbol, alias_isin, effective_from, effective_to,
     evidence_source, identity_evidence_url, lineage_evidence_url, notes)
VALUES
    ('NSE', 'CGCL', 'MMFSL', 'INE180C01018', DATE '2011-11-28', DATE '2012-08-07',
     'NSE official BhavCopy and listing evidence',
     'https://nsearchives.nseindia.com/content/press/28102010.htm',
     'https://nsearchives.nseindia.com/corporate/CGCL_10042026153109_CGCL_NewspaperAdvt_IssueOpening_NCDPI.pdf',
     'Step 39 verified MMFSL/INE180C01018 on both audited CGCL large-move dates. The range is intentionally limited to those evidence endpoints.'),
    ('NSE', 'COFORGE', 'NIITTECH', 'INE591G01017', DATE '2020-03-23', DATE '2020-03-25',
     'NSE official BhavCopy and issuer exchange filing',
     'https://nsearchives.nseindia.com/corporate/COFORGE_16112021040103_SEIntimation.pdf',
     'https://nsearchives.nseindia.com/corporate/COFORGE_16112021040103_SEIntimation.pdf',
     'Step 39 verified NIITTECH/INE591G01017 on both audited COFORGE large-move dates. The range is intentionally limited to those evidence endpoints.'),
    ('NSE', 'LTFOODS', 'DAAWAT', 'INE818H01012', DATE '2013-08-20', DATE '2013-08-20',
     'NSE official BhavCopy and symbol-change circular',
     'https://nsearchives.nseindia.com/content/circulars/CML59161.pdf',
     'https://nsearchives.nseindia.com/content/circulars/CML59161.pdf',
     'Step 39 verified DAAWAT/INE818H01012 on the audited LTFOODS large-move date. The range is intentionally limited to that evidence date.');

COMMENT ON TABLE instrument_identity_alias IS
    'Effective-dated, evidence-backed exchange identities used only to match historical official records; entries do not rewrite instrument or candle data. Batch 3 aliases are deliberately bounded by reviewed daily evidence.';
