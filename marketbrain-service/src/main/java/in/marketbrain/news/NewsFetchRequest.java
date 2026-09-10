package in.marketbrain.news;

public record NewsFetchRequest(
        NewsSourceDefinition source,
        int limit
) {
}
