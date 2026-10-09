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

    @Test
    void paperActionsRemainDisabledWithoutRegisteredAdapter() {
        when(stateStore.activeBinding()).thenReturn(Optional.of(new TelegramBinding(100,200,"Owner")));
        handler.handle(new TelegramUpdate(8,null,new TelegramCallback("paper-1",200,"private",100,"mbp:"+"a".repeat(43))));
        verify(client).answerCallback(eq("paper-1"),contains("not enabled"),eq(true));
        verify(actionProcessor,never()).process(any(),any());
    }

    @Test
    void springWiringStartsWithoutPaperAdapter() {
        new org.springframework.boot.test.context.runner.ApplicationContextRunner()
                .withPropertyValues("marketbrain.telegram.enabled=true")
                .withBean(TelegramBotClient.class,()->client).withBean(TelegramStateStore.class,()->stateStore)
                .withBean(TelegramActionProcessor.class,()->actionProcessor).withBean(MarketBrainProperties.class,this::properties)
                .withUserConfiguration(TelegramUpdateHandler.class)
                .run(context->{org.assertj.core.api.Assertions.assertThat(context).hasNotFailed().hasSingleBean(TelegramUpdateHandler.class);
                    org.assertj.core.api.Assertions.assertThat(context).doesNotHaveBean(in.marketbrain.paper.PaperApprovalCallback.class);});
    }

    @Test
    void paperAdapterOnlyReceivesBoundPrivateCallbacks()throws Exception {
        var paper=mock(in.marketbrain.paper.PaperApprovalCallback.class);
        @SuppressWarnings("unchecked") var provider=(org.springframework.beans.factory.ObjectProvider<in.marketbrain.paper.PaperApprovalCallback>)mock(org.springframework.beans.factory.ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(paper);
        var connected=new TelegramUpdateHandler(client,stateStore,actionProcessor,properties(),provider);
        when(stateStore.activeBinding()).thenReturn(Optional.of(new TelegramBinding(100,200,"Owner")));
        String data="mbp:"+"a".repeat(43);
        connected.handle(new TelegramUpdate(9,null,new TelegramCallback("wrong",200,"private",999,data)));
        connected.handle(new TelegramUpdate(10,null,new TelegramCallback("group",200,"group",100,data)));
        verify(paper,never()).handle(any(),org.mockito.ArgumentMatchers.anyLong(),org.mockito.ArgumentMatchers.anyLong(),any(),any());
        when(paper.handle("correct",100,200,"private",data)).thenReturn("Review only");
        connected.handle(new TelegramUpdate(11,null,new TelegramCallback("correct",200,"private",100,data)));
        verify(paper).handle("correct",100,200,"private",data);
        verify(client).answerCallback("correct","Review only",true);
        verify(actionProcessor,never()).process(any(),any());
    }

    @Test
    void databaseFailureMustNotAcknowledgeCallback()throws Exception {
        var paper=mock(in.marketbrain.paper.PaperApprovalCallback.class);
        @SuppressWarnings("unchecked") var provider=(org.springframework.beans.factory.ObjectProvider<in.marketbrain.paper.PaperApprovalCallback>)mock(org.springframework.beans.factory.ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(paper);
        when(stateStore.activeBinding()).thenReturn(Optional.of(new TelegramBinding(100,200,"Owner")));
        String data="mbp:"+"a".repeat(43);
        when(paper.handle("failure",100,200,"private",data)).thenThrow(new java.sql.SQLException("secret connection data"));
        var connected=new TelegramUpdateHandler(client,stateStore,actionProcessor,properties(),provider);
        var error=org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException.class,()->connected.handle(new TelegramUpdate(12,null,new TelegramCallback("failure",200,"private",100,data))));
        org.junit.jupiter.api.Assertions.assertFalse(error.toString().contains("secret"));
        verify(client,never()).answerCallback(eq("failure"),any(),org.mockito.ArgumentMatchers.anyBoolean());
    }

    private MarketBrainProperties properties() {
        return new MarketBrainProperties(
                "PAPER",
                new MarketBrainProperties.Paper(new BigDecimal("100000")),
                new MarketBrainProperties.Ollama("http://127.0.0.1:11434"),
                new MarketBrainProperties.Signal(90, 60),
                new MarketBrainProperties.PaytmMoney("https://developer.paytmmoney.com", false, ""),
                new MarketBrainProperties.Upstox(
                        "https://api.upstox.com", "https://example.test/NSE.json.gz", false, ""),
                new MarketBrainProperties.Telegram(true, "bot-token", "LOCAL-ONLY-CODE-1", 20, 1000, false)
        );
    }
}
