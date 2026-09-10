package in.marketbrain.news;

import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class NewsSourceCatalog {

    public List<NewsSourceDefinition> plannedSources() {
        return List.of(
                new NewsSourceDefinition(
                        "MARKETAUX_API",
                        "Marketaux API",
                        NewsSourceType.NEWS_API,
                        NewsSourceIntegrationType.MARKETAUX_API,
                        "https://www.marketaux.com/tos",
                        "Quota-controlled financial-news API candidate. Starts disabled until local API terms "
                                + "and the daily quota are accepted."
                ),
                new NewsSourceDefinition(
                        "ECONOMIC_TIMES_RSS",
                        "Economic Times RSS",
                        NewsSourceType.RSS,
                        NewsSourceIntegrationType.RSS_FEED,
                        "https://economictimes.indiatimes.com/rss.cms",
                        "Publisher RSS candidate. Starts disabled while written response is pending."
                ),
                new NewsSourceDefinition(
                        "LIVEMINT_RSS",
                        "Mint RSS",
                        NewsSourceType.RSS,
                        NewsSourceIntegrationType.RSS_FEED,
                        "https://www.livemint.com/rss",
                        "Publisher RSS candidate. Starts disabled while written response is pending."
                ),
                new NewsSourceDefinition(
                        "BUSINESS_STANDARD_RSS",
                        "Business Standard RSS",
                        NewsSourceType.RSS,
                        NewsSourceIntegrationType.RSS_FEED,
                        "https://www.business-standard.com/rss-feeds/listing",
                        "Publisher RSS candidate. Starts disabled while written response is pending."
                ),
                new NewsSourceDefinition(
                        "NSE_DISCLOSURES",
                        "NSE corporate disclosures",
                        NewsSourceType.OFFICIAL_DISCLOSURE,
                        NewsSourceIntegrationType.OFFICIAL_EVENTS,
                        "https://www.nseindia.com/companies-listing/corporate-filings-announcements",
                        "Official disclosure candidate. Starts disabled until published terms are reviewed."
                ),
                new NewsSourceDefinition(
                        "BSE_DISCLOSURES",
                        "BSE corporate announcements",
                        NewsSourceType.OFFICIAL_DISCLOSURE,
                        NewsSourceIntegrationType.OFFICIAL_EVENTS,
                        "https://www.bseindia.com/corporates/ann.html",
                        "Official disclosure candidate. Starts disabled until published terms are reviewed."
                ),
                new NewsSourceDefinition(
                        "SEBI_PUBLIC_UPDATES",
                        "SEBI public updates",
                        NewsSourceType.OFFICIAL_DISCLOSURE,
                        NewsSourceIntegrationType.OFFICIAL_EVENTS,
                        "https://www.sebi.gov.in/",
                        "Official regulatory update candidate. Starts disabled until published terms are reviewed."
                ),
                new NewsSourceDefinition(
                        "RBI_PRESS_RELEASES",
                        "RBI press releases",
                        NewsSourceType.OFFICIAL_DISCLOSURE,
                        NewsSourceIntegrationType.OFFICIAL_EVENTS,
                        "https://www.rbi.org.in/Scripts/BS_PressReleaseDisplay.aspx",
                        "Official macro and banking update candidate. Starts disabled until published terms are reviewed."
                )
        );
    }
}
