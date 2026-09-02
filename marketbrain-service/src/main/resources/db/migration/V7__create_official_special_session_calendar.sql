CREATE TABLE exchange_special_trading_session (
    exchange_code VARCHAR(16) NOT NULL,
    segment_code VARCHAR(16) NOT NULL,
    trading_date DATE NOT NULL,
    session_type VARCHAR(24) NOT NULL,
    session_name VARCHAR(160) NOT NULL,
    source_url VARCHAR(500) NOT NULL,
    PRIMARY KEY (exchange_code, segment_code, trading_date),
    CONSTRAINT ck_exchange_special_session_type CHECK (
        session_type IN ('MUHURAT', 'SPECIAL')
    )
);

COMMENT ON TABLE exchange_special_trading_session IS
    'Officially verified non-routine exchange sessions used to audit provider coverage; this is not a complete holiday calendar.';

INSERT INTO exchange_special_trading_session
    (exchange_code, segment_code, trading_date, session_type, session_name, source_url)
VALUES
    ('NSE', 'EQ', DATE '2011-10-26', 'MUHURAT', 'Diwali Muhurat trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2012.pdf'),
    ('NSE', 'EQ', DATE '2012-01-07', 'SPECIAL', 'Special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2012.pdf'),
    ('NSE', 'EQ', DATE '2012-03-03', 'SPECIAL', 'Special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2012.pdf'),
    ('NSE', 'EQ', DATE '2012-04-28', 'SPECIAL', 'Special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2013.pdf'),
    ('NSE', 'EQ', DATE '2012-09-08', 'SPECIAL', 'Special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2013.pdf'),
    ('NSE', 'EQ', DATE '2013-05-11', 'SPECIAL', 'Special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2014.pdf'),
    ('NSE', 'EQ', DATE '2013-11-03', 'MUHURAT', 'Diwali Muhurat trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2014.pdf'),
    ('NSE', 'EQ', DATE '2014-03-22', 'SPECIAL', 'Special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2014.pdf'),
    ('NSE', 'EQ', DATE '2015-02-28', 'SPECIAL', 'Union Budget special trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/NSEIL_Annual_Report_2015.pdf'),
    ('NSE', 'EQ', DATE '2016-10-30', 'MUHURAT', 'Diwali Muhurat trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/annualreport16-17.pdf'),
    ('NSE', 'EQ', DATE '2017-10-19', 'MUHURAT', 'Diwali Muhurat trading session',
     'https://nsearchives.nseindia.com/global/content/about_us/nseannualreport26agm.pdf'),
    ('NSE', 'EQ', DATE '2018-11-07', 'MUHURAT', 'Diwali Muhurat trading session',
     'https://nsearchives.nseindia.com/content/circulars/CMTR36475.pdf');
