package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class OfficialSpecialSessionCalendarTest {

    @Test
    void migrationContainsEveryVerifiedPilotSpecialSessionWithProvenance() throws IOException {
        String migration = migrationText();
        List<String> verifiedDates = List.of(
                "2011-10-26", "2012-01-07", "2012-03-03", "2012-04-28",
                "2012-09-08", "2013-05-11", "2013-11-03", "2014-03-22",
                "2015-02-28", "2016-10-30", "2017-10-19", "2018-11-07"
        );

        assertThat(verifiedDates).allSatisfy(date ->
                assertThat(migration).contains("DATE '" + date + "'"));
        assertThat(migration).contains("'MUHURAT'").contains("'SPECIAL'");
        assertThat(migration).contains("nseindia.com");
        assertThat(migration).doesNotContain("DELETE FROM market_candle");
        assertThat(migration).doesNotContain("UPDATE market_candle");
    }

    private String migrationText() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V7__create_official_special_session_calendar.sql")) {
            assertThat(stream).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
