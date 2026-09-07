package in.marketbrain.marketdata.daily;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.util.Optional;

@Component
public class DailyEnrichmentScheduler {

    private static final Logger LOGGER = LoggerFactory.getLogger(DailyEnrichmentScheduler.class);

    private final DailyEnrichmentService service;
    private final DailyEnrichmentProviderReadinessService readinessService;
    private final DailyEnrichmentNotificationService notificationService;
    private final DailyEnrichmentProperties properties;
    private final HistoricalBackfillProperties backfillProperties;

    public DailyEnrichmentScheduler(
            DailyEnrichmentService service,
            DailyEnrichmentProviderReadinessService readinessService,
            DailyEnrichmentNotificationService notificationService,
            DailyEnrichmentProperties properties,
            HistoricalBackfillProperties backfillProperties
    ) {
        this.service = service;
        this.readinessService = readinessService;
        this.notificationService = notificationService;
        this.properties = properties;
        this.backfillProperties = backfillProperties;
    }

    @Scheduled(
            cron = "${marketbrain.daily-enrichment.cron}",
            zone = "${marketbrain.daily-enrichment.zone}"
    )
    public void collectAfterMarket() {
        collect(false);
    }

    @Scheduled(
            cron = "${marketbrain.daily-enrichment.final-attempt-cron}",
            zone = "${marketbrain.daily-enrichment.zone}"
    )
    public void collectAtCutoff() {
        collect(true);
    }

    private void collect(boolean finalAttempt) {
        if (!properties.schedulerEnabled()) {
            return;
        }
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of(properties.zone()));
        LocalTime start = LocalTime.parse(properties.providerWindowStart());
        LocalTime cutoff = LocalTime.parse(properties.providerWindowCutoff());
        if (now.toLocalTime().isBefore(start)
                || (!finalAttempt && !now.toLocalTime().isBefore(cutoff))) {
            return;
        }
        LocalDate targetDate = now.toLocalDate();
        if (!backfillProperties.workerEnabled()) {
            LOGGER.warn("Daily enrichment scheduler is enabled but the persisted collection worker is disabled.");
            if (finalAttempt) {
                notificationService.sendWarning(targetDate, null, cutoffWarning(
                        targetDate, "COLLECTION_WORKER_DISABLED"));
            }
            return;
        }
        try {
            Optional<DailyEnrichmentRunSummary> existing = service.findForTarget(targetDate);
            if (existing.isPresent()) {
                DailyEnrichmentRunSummary run = existing.get();
                if ("CREATED".equals(run.status())) {
                    service.start(run.runId());
                    LOGGER.info("Recovered and started daily enrichment run {} for {}.",
                            run.runId(), targetDate);
                }
                return;
            }
            DailyEnrichmentProviderReadiness readiness = readinessService.check(targetDate);
            if (!readiness.ready()) {
                LOGGER.info("Daily enrichment is waiting for provider readiness for {}: {}.",
                        targetDate, readiness.status());
                if (finalAttempt) {
                    notificationService.sendWarning(targetDate, null,
                            cutoffWarning(targetDate, readiness.status()));
                }
                return;
            }
            DailyEnrichmentPreview preview = service.preview(targetDate);
            if (preview.blockedInstruments() > 0) {
                LOGGER.error("Daily enrichment was not created because {} instruments are blocked.",
                        preview.blockedInstruments());
                if (finalAttempt) {
                    notificationService.sendWarning(targetDate, null,
                            cutoffWarning(targetDate, "INSTRUMENTS_BLOCKED_" + preview.blockedInstruments()));
                }
                return;
            }
            if (preview.fetchInstruments() == 0) {
                LOGGER.info("Daily enrichment is already current through {}.", targetDate);
                notificationService.sendCompletion(targetDate, null, alreadyCurrentMessage(targetDate));
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
            if (finalAttempt) {
                notificationService.sendWarning(targetDate, null,
                        cutoffWarning(targetDate, "SCHEDULER_CHECK_FAILED"));
            }
        }
    }

    private String alreadyCurrentMessage(LocalDate targetDate) {
        return """
                [DAILY DATA COMPLETE] PAPER MODE
                Trading date: %s
                All 500 instruments were already current; no collection run was required.
                Data collection only; no trading action is required.
                """.formatted(targetDate).strip();
    }

    private String cutoffWarning(LocalDate targetDate, String reason) {
        return """
                [DAILY DATA WARNING] PAPER MODE
                Trading date: %s
                Reason: %s
                No automatic daily run was started by the 18:00 provider-readiness cutoff.
                The next weekday window will catch up from each instrument's latest stored date.
                Stale data remains non-actionable; no trading action is required.
                """.formatted(targetDate, reason).strip();
    }
}
