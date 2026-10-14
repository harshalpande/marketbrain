package in.marketbrain.telegram;

import in.marketbrain.configuration.MarketBrainProperties;
import in.marketbrain.paper.PaperApprovalCallback;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import java.sql.SQLException;
import java.util.*;
import static org.mockito.Mockito.*;

/** Real poll/handler code with offline transport/store doubles; no Telegram or database connection. */
class TelegramPaperPollingTest {
    @SuppressWarnings("unchecked")
    @Test void lockedClickIsExplicitlyNotProcessedAndDoesNotBlockFollowingStatus() throws Exception {
        var client=mock(TelegramBotClient.class);var state=mock(TelegramStateStore.class);
        var legacy=mock(TelegramActionProcessor.class);var callback=mock(PaperApprovalCallback.class);
        var provider=(ObjectProvider<PaperApprovalCallback>)mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(callback);
        var app=new MarketBrainProperties("PAPER",null,null,null,null,null,
                new MarketBrainProperties.Telegram(true,"synthetic","SYNTHETIC_PAIR_CODE",20,1000,false));
        when(state.activeBinding()).thenReturn(Optional.of(new TelegramBinding(111,222,"fixture")));
        when(state.nextUpdateOffset()).thenReturn(7L);
        String data="mbp:"+"a".repeat(43);
        when(callback.handle("callback",111,222,"private",data)).thenThrow(new in.marketbrain.paper.PaperRuntimeCredential.Locked());
        when(client.getUpdates(7)).thenReturn(List.of(
                new TelegramUpdate(7,null,new TelegramCallback("callback",222,"private",111,data)),
                new TelegramUpdate(8,new TelegramMessage(222,"private",111,"fixture","/status"),null)));
        new TelegramPollingService(client,state,new TelegramUpdateHandler(client,state,legacy,app,provider)).poll();
        verify(client).answerCallback(eq("callback"),contains("This click was not processed"),eq(true));
        verify(client).sendMessage(eq(222L),contains("MarketBrain is connected"),isNull());
        verify(state).saveNextUpdateOffset(8);verify(state).saveNextUpdateOffset(9);
        verifyNoInteractions(legacy);
    }
    @SuppressWarnings("unchecked")
    @Test void databaseFailureKeepsCursorThenRestartReplaysAndAcknowledges() throws Exception {
        var client = mock(TelegramBotClient.class);
        var state = mock(TelegramStateStore.class);
        var legacy = mock(TelegramActionProcessor.class);
        var callback = mock(PaperApprovalCallback.class);
        var provider = (ObjectProvider<PaperApprovalCallback>) mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(callback);
        var app = new MarketBrainProperties("PAPER", null, null, null, null, null,
                new MarketBrainProperties.Telegram(true, "synthetic", "SYNTHETIC_PAIR_CODE", 20, 1000, false));
        var handler = new TelegramUpdateHandler(client, state, legacy, app, provider);
        when(state.activeBinding()).thenReturn(Optional.of(new TelegramBinding(111, 222, "fixture")));
        when(state.nextUpdateOffset()).thenReturn(7L);
        String data = "mbp:" + "a".repeat(43);
        when(client.getUpdates(7)).thenReturn(List.of(new TelegramUpdate(7, null,
                new TelegramCallback("callback", 222, "private", 111, data))));
        when(callback.handle("callback", 111, 222, "private", data))
                .thenThrow(new SQLException("synthetic sensitive failure"))
                .thenReturn("PAPER proposal rejected. No trade created.");
        new TelegramPollingService(client, state, handler).poll();
        verify(state, never()).saveNextUpdateOffset(anyLong());
        verify(client, never()).answerCallback(anyString(), anyString(), anyBoolean());
        // Fresh worker after restart: saved cursor still points at the unprocessed action.
        new TelegramPollingService(client, state, handler).poll();
        var order = inOrder(callback, client, state);
        order.verify(callback, times(2)).handle("callback", 111, 222, "private", data);
        order.verify(client).answerCallback("callback", "PAPER proposal rejected. No trade created.", true);
        order.verify(state).saveNextUpdateOffset(8L);
        verifyNoInteractions(legacy);
    }
}
