package in.marketbrain.telegram;

import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class TelegramUpdateHandlerTest {

    private TelegramBotClient client;
    private TelegramStateStore stateStore;
    private TelegramActionProcessor actionProcessor;
    private TelegramUpdateHandler handler;

    @BeforeEach
    void setUp() {
        client = mock(TelegramBotClient.class);
        stateStore = mock(TelegramStateStore.class);
        actionProcessor = mock(TelegramActionProcessor.class);
        handler = new TelegramUpdateHandler(client, stateStore, actionProcessor, properties());
    }

    @Test
    void startDoesNotPairAnUnknownPrivateUser() {
        when(stateStore.activeBinding()).thenReturn(Optional.empty());

        handler.handle(updateWithMessage("/start", 100, 200));

        verify(stateStore, never()).pair(any());
        verify(client).sendMessage(eq(200L), contains("awaiting secure pairing"), eq(null));
    }

    @Test
    void correctPairingCodeBindsTheFirstPrivateUser() {
        when(stateStore.activeBinding()).thenReturn(Optional.empty());
        when(stateStore.pair(any())).thenReturn(true);

        handler.handle(updateWithMessage("/pair LOCAL-ONLY-CODE-1", 100, 200));

        verify(stateStore).pair(new TelegramBinding(100, 200, "Harshal Pande"));
        verify(client).sendMessage(eq(200L), contains("paired successfully"), eq(null));
    }

    @Test
    void messagesFromASecondIdentityAreIgnoredAfterPairing() {
        when(stateStore.activeBinding()).thenReturn(
                Optional.of(new TelegramBinding(100, 200, "Harshal Pande")));

        handler.handle(updateWithMessage("/status", 999, 888));

        verify(client, never()).sendMessage(any(Long.class), any(), any());
    }

    @Test
    void authorizedOpaqueCallbackIsDelegatedAndAnswered() {
        when(stateStore.activeBinding()).thenReturn(
                Optional.of(new TelegramBinding(100, 200, "Harshal Pande")));
        TelegramCallback callback = new TelegramCallback("callback-1", 200, "private", 100, "mb:opaque-token");
        when(actionProcessor.process(callback, "opaque-token"))
                .thenReturn(new TelegramActionResult("Handled", true));

        handler.handle(new TelegramUpdate(7, null, callback));

        verify(actionProcessor).process(callback, "opaque-token");
        verify(client).answerCallback("callback-1", "Handled", true);
    }

    private TelegramUpdate updateWithMessage(String text, long userId, long chatId) {
        return new TelegramUpdate(
                1,
                new TelegramMessage(chatId, "private", userId, "Harshal Pande", text),
                null);
    }

    private MarketBrainProperties properties() {
        return new MarketBrainProperties(
                "PAPER",
                new MarketBrainProperties.Paper(new BigDecimal("100000")),
                new MarketBrainProperties.Ollama("http://127.0.0.1:11434"),
                new MarketBrainProperties.Signal(90, 60),
                new MarketBrainProperties.PaytmMoney("https://developer.paytmmoney.com", false, ""),
                new MarketBrainProperties.Telegram(true, "bot-token", "LOCAL-ONLY-CODE-1", 20, 1000, false)
        );
    }
}
