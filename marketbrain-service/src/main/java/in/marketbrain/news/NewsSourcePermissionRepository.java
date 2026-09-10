package in.marketbrain.news;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Repository
class NewsSourcePermissionRepository {

    private final JdbcClient jdbc;

    NewsSourcePermissionRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Map<String, NewsSourcePermissionRecord> recordsBySourceKey() {
        return jdbc.sql("""
                        SELECT source_key,
                               permission_status,
                               integration_enabled,
                               retention_days,
                               headline_storage_allowed,
                               snippet_storage_allowed,
                               local_ai_processing_allowed,
                               derived_data_retention_allowed,
                               attribution_required
                        FROM news_source_permission_register
                        ORDER BY source_key
                        """)
                .query((rs, rowNum) -> new NewsSourcePermissionRecord(
                        rs.getString("source_key"),
                        rs.getString("permission_status"),
                        rs.getBoolean("integration_enabled"),
                        (Integer) rs.getObject("retention_days"),
                        rs.getBoolean("headline_storage_allowed"),
                        rs.getBoolean("snippet_storage_allowed"),
                        rs.getBoolean("local_ai_processing_allowed"),
                        rs.getBoolean("derived_data_retention_allowed"),
                        rs.getBoolean("attribution_required")))
                .list()
                .stream()
                .collect(Collectors.toMap(NewsSourcePermissionRecord::sourceKey, Function.identity()));
    }
}
