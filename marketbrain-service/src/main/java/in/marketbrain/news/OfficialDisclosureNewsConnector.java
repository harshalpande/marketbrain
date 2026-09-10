package in.marketbrain.news;

import org.springframework.stereotype.Component;

@Component
class OfficialDisclosureNewsConnector implements NewsConnector {

    @Override
    public NewsSourceIntegrationType integrationType() {
        return NewsSourceIntegrationType.OFFICIAL_EVENTS;
    }

    @Override
    public boolean liveFetchCapable() {
        return false;
    }

    @Override
    public NewsFetchResult fetch(NewsFetchRequest request) {
        return NewsFetchResult.skipped(
                request.source().sourceKey(),
                "Official source adapter is registered but source-specific extraction remains disabled until terms "
                        + "review and parser review are complete.");
    }
}
