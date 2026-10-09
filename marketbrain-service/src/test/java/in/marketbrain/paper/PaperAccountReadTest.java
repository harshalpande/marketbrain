package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import static in.marketbrain.paper.PaperAccountReadService.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class PaperAccountReadTest {
    private static final String TOKEN = "a".repeat(64);
    private static final String ROUTE = "/api/v1/paper/account/overview";
    private static final Instant NOW = Instant.parse("2026-10-09T00:00:00Z");
    private Account account(String start, String cash) { return new Account("1", "Default Paper Portfolio", "PAPER", start, cash); }
    private Overview normal() { return assess(List.of(account("100000.00", "100000.00")), false, false, NOW); }

    @Test void emptySeedIsOnlyReviewableNeverExecutionReady() {
        var result = normal();
        assertEquals("EMPTY_ACCOUNT_REVIEWABLE", result.migrationAssessment());
        assertEquals("READ_ONLY_EXECUTION_BLOCKED", result.status());
        assertEquals(3, result.blockers().size());
        assertFalse(result.databaseWritesPerformed()); assertFalse(result.actionExecutionEnabled());
        assertFalse(result.liveExecutionEnabled());
    }
    @Test void missingAccountNeverReseeds() {
        var result = assess(List.of(), false, false, NOW);
        assertNull(result.account()); assertTrue(result.blockers().contains("NO_ACTIVE_ACCOUNT_DO_NOT_RESEED"));
    }
    @Test void multipleAccountsNeverChoosesOne() {
        var result = assess(List.of(account("100000", "100000"), account("100000", "100000")), false, false, NOW);
        assertNull(result.account()); assertTrue(result.activeAccountCountIsLowerBound());
        assertEquals("REVIEW_REQUIRED", result.migrationAssessment());
    }
    @ParameterizedTest @ValueSource(strings = {"0.00", "90000.25", "100001.00"})
    void preservesChangedCashForReview(String cash) {
        var result = assess(List.of(account("100000.00", cash)), false, false, NOW);
        assertEquals(cash, result.account().currentCash()); assertEquals("REVIEW_REQUIRED", result.migrationAssessment());
    }
    @ParameterizedTest @ValueSource(strings = {"-1", "1.001", "garbage", "9999999999999999999"})
    void invalidMoneyBlocks(String cash) {
        assertTrue(assess(List.of(account("100000.00", cash)), false, false, NOW).blockers().contains("ACCOUNT_CASH_INVALID"));
    }
    @Test void wrongOpeningCashAndModeBlock() {
        assertEquals("REVIEW_REQUIRED", assess(List.of(account("50000", "50000")), false, false, NOW).migrationAssessment());
        var other = new Account("1", "legacy", "LIVE", "100000", "100000");
        assertTrue(assess(List.of(other), false, false, NOW).blockers().contains("ACCOUNT_MODE_INVALID"));
    }
    @Test void eitherOrdersOrFillsRequireMigrationReview() {
        for (boolean orders : List.of(true, false)) {
            assertTrue(assess(List.of(account("100000", "100000")), orders, !orders, NOW)
                    .blockers().contains("LEGACY_HISTORY_REQUIRES_MIGRATION_REVIEW"));
        }
    }
    @Test @SuppressWarnings("unchecked") void jdbcUsesBoundedAccountAndLedgerReads() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        ResultSet rs = mock(ResultSet.class);
        when(rs.getLong("id")).thenReturn(7L); when(rs.getString("name")).thenReturn("Saved account");
        when(rs.getString("execution_mode")).thenReturn("PAPER");
        when(rs.getBigDecimal("starting_cash")).thenReturn(new BigDecimal("100000.00"));
        when(rs.getBigDecimal("current_cash")).thenReturn(new BigDecimal("91234.56"));
        when(jdbc.query(anyString(), any(RowMapper.class))).thenAnswer(inv -> {
            String sql = inv.getArgument(0);
            assertTrue(sql.stripLeading().startsWith("SELECT"));
            assertTrue(sql.contains("ORDER BY id LIMIT"));
            if (sql.contains("paper_portfolio")) return List.of(((RowMapper<?>) inv.getArgument(1)).mapRow(rs, 0));
            return List.of();
        });
        var result = new PaperAccountReadService(jdbc).overview();
        assertEquals("7", result.account().id()); assertEquals("91234.56", result.account().currentCash());
        assertEquals(4, mockingDetails(jdbc).getInvocations().size());
    }
    @Test void transactionIsBoundedConsistentAndReadOnly() throws Exception {
        var tx = PaperAccountReadService.class.getMethod("overview").getAnnotation(Transactional.class);
        assertTrue(tx.readOnly()); assertEquals(Isolation.REPEATABLE_READ, tx.isolation()); assertEquals(10, tx.timeout());
    }
    @Test void springResolvesConstructorAndTokenProperty() {
        try (var context = new AnnotationConfigApplicationContext()) {
            context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test", Map.of("marketbrain.paper.read-token", TOKEN)));
            context.registerBean(JdbcTemplate.class, () -> mock(JdbcTemplate.class));
            context.register(PaperAccountReadService.class, PaperAccountReadController.class); context.refresh();
            assertNotNull(context.getBean(PaperAccountReadController.class));
        }
    }
    @ParameterizedTest @ValueSource(strings = {"", "short", "bad token with spaces that must not work", "a"})
    void disabledConfigurationNeverReadsDatabase(String configured) throws Exception {
        var service = mock(PaperAccountReadService.class);
        var mvc = MockMvcBuilders.standaloneSetup(new PaperAccountReadController(service, configured, "PAPER")).build();
        mvc.perform(get(ROUTE)).andExpect(status().isServiceUnavailable()); verifyNoInteractions(service);
    }
    @Test void liveModeDisablesReadAccess() throws Exception {
        var service = mock(PaperAccountReadService.class);
        MockMvcBuilders.standaloneSetup(new PaperAccountReadController(service, TOKEN, "LIVE")).build()
                .perform(get(ROUTE).header("X-MarketBrain-Paper-Read-Token", TOKEN)).andExpect(status().isServiceUnavailable());
        verifyNoInteractions(service);
    }
    @Test void missingWrongAndOversizedTokenNeverRead() throws Exception {
        var service = mock(PaperAccountReadService.class);
        var mvc = MockMvcBuilders.standaloneSetup(new PaperAccountReadController(service, TOKEN, "PAPER")).build();
        mvc.perform(get(ROUTE)).andExpect(status().isUnauthorized());
        for (String token : List.of("b".repeat(64), "a".repeat(129), "short")) {
            mvc.perform(get(ROUTE).header("X-MarketBrain-Paper-Read-Token", token)).andExpect(status().isUnauthorized());
        }
        verifyNoInteractions(service);
    }
    @Test void successIsNoStoreAndCannotPost() throws Exception {
        var service = mock(PaperAccountReadService.class); when(service.overview()).thenReturn(normal());
        var mvc = MockMvcBuilders.standaloneSetup(new PaperAccountReadController(service, TOKEN, "PAPER")).build();
        mvc.perform(get(ROUTE).header("X-MarketBrain-Paper-Read-Token", TOKEN)).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.account.currentCash").value("100000.00"))
                .andExpect(jsonPath("$.actionExecutionEnabled").value(false));
        mvc.perform(post(ROUTE).header("X-MarketBrain-Paper-Read-Token", TOKEN)).andExpect(status().isMethodNotAllowed());
        verify(service, times(1)).overview();
    }
    @Test void databaseFailureDoesNotExposeDetails() throws Exception {
        var service = mock(PaperAccountReadService.class);
        when(service.overview()).thenThrow(new DataAccessResourceFailureException("secret SQL host password"));
        var result = MockMvcBuilders.standaloneSetup(new PaperAccountReadController(service, TOKEN, "PAPER")).build()
                .perform(get(ROUTE).header("X-MarketBrain-Paper-Read-Token", TOKEN)).andExpect(status().isServiceUnavailable()).andReturn();
        assertFalse(result.getResponse().getContentAsString().contains("secret"));
        assertFalse(result.getResponse().getErrorMessage().contains("secret"));
    }
}
