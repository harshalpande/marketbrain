package in.marketbrain.feature;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class DailyFeatureSnapshotScheduler {

    private static final Logger LOGGER = LoggerFactory.getLogger(DailyFeatureSnapshotScheduler.class);

    private final DailyFeatureSnapshotAutomationService service;

    public DailyFeatureSnapshotScheduler(DailyFeatureSnapshotAutomationService service) {
        this.service = service;
    }

    @Scheduled(fixedDelayString = "${marketbrain.daily-feature-snapshot.monitor-delay-millis}")
    public void processCompletedDailyRuns() {
        try {
            service.runOnce();
        } catch (RuntimeException exception) {
            LOGGER.error("Daily feature scheduler stopped safely: {}.",
                    exception.getClass().getSimpleName());
        }
    }
}
