package in.marketbrain.marketdata.daily;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.ZoneId;

@Component
public class DailyEnrichmentScheduler {

    private static final Logger LOGGER = LoggerFactory.getLogger(DailyEnrichmentScheduler.class);

    private final DailyEnrichmentService service;
    private final DailyEnrichmentProperties properties;
    private final HistoricalBackfillProperties backfillProperties;

    public DailyEnrichmentScheduler(
            DailyEnrichmentService service,
            DailyEnrichmentProperties properties,
            HistoricalBackfillProperties backfillProperties
    ) {
        this.service = service;
        this.properties = properties;
        this.backfillProperties = backfillProperties;
    }

    @Scheduled(
            cron = "${marketbrain.daily-enrichment.cron}",
            zone = "${marketbrain.daily-enrichment.zone}"
    )
    public void collectAfterMarket() {
        if (!properties.schedulerEnabled()) {
            return;
        }
        if (!backfillProperties.workerEnabled()) {
            LOGGER.warn("Daily enrichment scheduler is enabled but the persisted collection worker is disabled.");
            return;
        }
        try {
            LocalDate targetDate = LocalDate.now(ZoneId.of(properties.zone()));
            DailyEnrichmentPreview preview = service.preview(targetDate);
            if (preview.blockedInstruments() > 0) {
                LOGGER.error("Daily enrichment was not created because {} instruments are blocked.",
                        preview.blockedInstruments());
                return;
            }
            if (preview.fetchInstruments() == 0) {
                LOGGER.info("Daily enrichment is already current through {}.", targetDate);
                return;
            }
            DailyEnrichmentRunSummary run = service.create(targetDate, preview.manifestHash());
            if ("CREATED".equals(run.status())) {
                service.start(run.runId());
                LOGGER.info("Daily enrichment run {} started for {} instruments through {}.",
                        run.runId(), run.instruments(), targetDate);
            } else {
                LOGGER.info("Daily enrichment run {} already exists with status {}.", run.runId(), run.status());
            }
        } catch (RuntimeException exception) {
            LOGGER.error("Daily enrichment scheduling stopped safely: {}", exception.getClass().getSimpleName());
        }
    }
}
