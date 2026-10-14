package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperRuntimeCredentialTest {
    static byte[] secret() { return "ab".repeat(32).getBytes(StandardCharsets.US_ASCII); }
    @Test void startsLockedAndFreshInstancesNeverInheritSecrets() {
        try (var c = new PaperRuntimeCredential()) {
            assertFalse(c.ready()); assertThrows(PaperRuntimeCredential.Locked.class, c::read);
            c.unlock(secret()); assertTrue(c.ready());
            try (var restart = new PaperRuntimeCredential()) { assertFalse(restart.ready()); }
        }
    }
    @Test void copiesInputAndReturnsFreshCallerOwnedBuffers() {
        try (var c = new PaperRuntimeCredential()) {
            byte[] input = secret(); c.unlock(input); Arrays.fill(input, (byte)0);
            char[] first = c.read(); Arrays.fill(first, '\0');
            assertEquals("ab".repeat(32), new String(c.read()));
            c.lock(); assertFalse(c.ready()); assertThrows(PaperRuntimeCredential.Locked.class, c::read);
        }
    }
    @Test void replayIsIdempotentButDifferentPasswordCannotReplaceWithoutLock() {
        try (var c = new PaperRuntimeCredential()) {
            c.unlock(secret()); c.unlock(secret());
            assertThrows(IllegalStateException.class, () -> c.unlock("cd".repeat(32).getBytes(StandardCharsets.US_ASCII)));
            assertEquals("ab".repeat(32), new String(c.read()));
            c.lock(); c.unlock("cd".repeat(32).getBytes(StandardCharsets.US_ASCII));
            assertEquals("cd".repeat(32), new String(c.read()));
        }
    }
    @Test void malformedInputCannotUnlockOrDestroyExistingSecret() {
        try (var c = new PaperRuntimeCredential()) {
            for (byte[] input : new byte[][]{null, new byte[0], new byte[63], new byte[65], new byte[64],
                    "AB".repeat(32).getBytes(StandardCharsets.US_ASCII)}) {
                assertThrows(IllegalArgumentException.class, () -> c.unlock(input)); assertFalse(c.ready());
            }
            c.unlock(secret()); assertThrows(IllegalArgumentException.class, () -> c.unlock(new byte[64]));
            assertEquals("ab".repeat(32), new String(c.read()));
        }
    }
    @Test void closedInstanceCannotBeReopened() {
        var c = new PaperRuntimeCredential(); c.unlock(secret()); c.close(); c.close();
        assertFalse(c.ready()); assertThrows(PaperRuntimeCredential.Locked.class, () -> c.unlock(secret()));
    }
    @Test void lockedCallbackNeverTouchesDatabaseOrQuoteSource() throws Exception {
        var review = mock(PaperApprovalReview.class);
        try (var c = new PaperRuntimeCredential()) {
            var cb = new PaperApprovalCallback(review, c::ready);
            assertThrows(PaperRuntimeCredential.Locked.class, () -> cb.handle("a",1,1,"private","mbp:"+"a".repeat(43)));
            verifyNoInteractions(review);
        }
    }
    @Test void invalidTransportIsRejectedEvenWhileLocked() {
        var review = mock(PaperApprovalReview.class);
        var cb = new PaperApprovalCallback(review, () -> false);
        assertThrows(IllegalArgumentException.class, () -> cb.handle("a",1,1,"group","mbp:"+"a".repeat(43)));
        verifyNoInteractions(review);
    }
    @Test void concurrentReadsNeverReturnPartialSecrets() throws Exception {
        try (var c = new PaperRuntimeCredential(); var pool = java.util.concurrent.Executors.newFixedThreadPool(3)) {
            var writer = pool.submit(() -> { for (int i=0;i<1000;i++) {c.unlock(secret());c.lock();} });
            var reader = pool.submit(() -> { for (int i=0;i<1000;i++) {
                try { char[] copy = c.read(); assertEquals("ab".repeat(32), new String(copy)); Arrays.fill(copy,'\0'); }
                catch (PaperRuntimeCredential.Locked expected) { }
            }});
            writer.get(10,java.util.concurrent.TimeUnit.SECONDS); reader.get(10,java.util.concurrent.TimeUnit.SECONDS);
        }
    }
}
