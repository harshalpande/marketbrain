package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ExpansionBatchSelectorTest {

    private final ExpansionBatchSelector selector = new ExpansionBatchSelector();

    @Test
    void excludesPilotAndCompletedStocksThenBuildsADeterministicBoundedBatch() {
        var candidates = List.of(
                candidate(5, "TCS"), candidate(4, "ZEEL"), candidate(3, "ASIANPAINT"),
                candidate(2, "INFY"), candidate(1, "BAJFINANCE")
        );

        var selection = selector.select(candidates, List.of("INFY", "TCS"), Set.of(1L), 1);

        assertThat(selection.selected()).extracting(ExpansionBatchSelector.Candidate::symbol)
                .containsExactly("ASIANPAINT");
        assertThat(selection.remainingAfterBatch()).isEqualTo(1);
    }

    @Test
    void returnsEveryRemainingStockWhenFinalBatchIsSmallerThanLimit() {
        var selection = selector.select(
                List.of(candidate(1, "AAA"), candidate(2, "BBB")), List.of(), Set.of(), 50);

        assertThat(selection.selected()).hasSize(2);
        assertThat(selection.remainingAfterBatch()).isZero();
    }

    @Test
    void rejectsNonPositiveBatchSize() {
        assertThatThrownBy(() -> selector.select(List.of(), List.of(), Set.of(), 0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("positive");
    }

    private ExpansionBatchSelector.Candidate candidate(long id, String symbol) {
        return new ExpansionBatchSelector.Candidate(id, "NSE_EQ|" + id, symbol);
    }
}
