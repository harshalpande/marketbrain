package in.marketbrain.telegram;

import java.util.Optional;

interface TelegramStateStore {

    Optional<TelegramBinding> activeBinding();

    boolean pair(TelegramBinding binding);

    void recordInteraction(long userId, long chatId);

    long nextUpdateOffset();

    void saveNextUpdateOffset(long offset);
}
