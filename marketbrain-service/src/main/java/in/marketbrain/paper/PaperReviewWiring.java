package in.marketbrain.paper;

import java.nio.file.*;
import java.time.Clock;
import java.util.Arrays;
import java.util.Objects;

/** Dedicated review connection only. No publisher, ledger writer, datasource fallback or execution API. */
public final class PaperReviewWiring {
    private PaperReviewWiring() {}

    public static PaperApprovalCallback callback(PaperWriterConnector.Target target, Path credentialFile,
            PaperApprovalReview.QuoteSource quotes, Clock clock, PaperApprovalReview.PolicyVersion policy) {
        Objects.requireNonNull(target); Objects.requireNonNull(credentialFile);
        Objects.requireNonNull(quotes); Objects.requireNonNull(clock); Objects.requireNonNull(policy);
        if (!credentialFile.isAbsolute()) throw new IllegalArgumentException("Absolute writer credential file required");
        var connector = new PaperWriterConnector(target, () -> readCredential(credentialFile), true);
        return new PaperApprovalCallback(PaperApprovalReview.restrictedWriter(connector, quotes, clock, policy));
    }

    /** Fresh 256-bit hex credential, not the approval encryption key. Read at each connection, never cached. */
    static char[] readCredential(Path file) throws Exception {
        byte[] encoded = null;
        try {
            if (!file.isAbsolute()) throw new IllegalArgumentException();
            for (Path part = file; part != null; part = part.getParent()) {
                if (Files.isSymbolicLink(part)) throw new IllegalArgumentException();
            }
            if (!Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS)) throw new IllegalArgumentException();
            try (var input = Files.newInputStream(file, LinkOption.NOFOLLOW_LINKS)) { encoded = input.readNBytes(67); }
            if (encoded.length != 64 && !(encoded.length == 65 && encoded[64] == '\n')
                    && !(encoded.length == 66 && encoded[64] == '\r' && encoded[65] == '\n'))
                throw new IllegalArgumentException();
            for (int i = 0; i < 64; i++) {
                int ch = encoded[i];
                if (!(ch >= '0' && ch <= '9' || ch >= 'a' && ch <= 'f' || ch >= 'A' && ch <= 'F'))
                    throw new IllegalArgumentException();
            }
            char[] result = new char[64];
            for (int i = 0; i < result.length; i++) result[i] = (char) encoded[i];
            return result;
        } catch (Exception invalid) {
            // File paths, contents and OS error details must not enter callback/provider diagnostics.
            throw new IllegalArgumentException("Writer credential file unavailable or invalid");
        } finally { if (encoded != null) Arrays.fill(encoded, (byte) 0); }
    }
}
