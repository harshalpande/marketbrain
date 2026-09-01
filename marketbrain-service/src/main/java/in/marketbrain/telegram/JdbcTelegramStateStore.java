package in.marketbrain.telegram;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
class JdbcTelegramStateStore implements TelegramStateStore {

    private final JdbcClient jdbc;

    JdbcTelegramStateStore(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<TelegramBinding> activeBinding() {
        return jdbc.sql("""
                        SELECT telegram_user_id, telegram_chat_id, display_name
                        FROM telegram_binding
                        WHERE binding_key = 'PRIMARY' AND active = TRUE
                        """)
                .query((rs, rowNum) -> new TelegramBinding(
                        rs.getLong("telegram_user_id"),
                        rs.getLong("telegram_chat_id"),
                        rs.getString("display_name")))
                .optional();
    }

    @Override
    public boolean pair(TelegramBinding binding) {
        return jdbc.sql("""
                        INSERT INTO telegram_binding
                            (binding_key, telegram_user_id, telegram_chat_id, display_name)
                        VALUES ('PRIMARY', :userId, :chatId, :displayName)
                        ON CONFLICT DO NOTHING
                        """)
                .param("userId", binding.userId())
                .param("chatId", binding.chatId())
                .param("displayName", binding.displayName())
                .update() == 1;
    }

    @Override
    public void recordInteraction(long userId, long chatId) {
        jdbc.sql("""
                        UPDATE telegram_binding
                        SET last_interaction_at = CURRENT_TIMESTAMP
                        WHERE binding_key = 'PRIMARY'
                          AND telegram_user_id = :userId
                          AND telegram_chat_id = :chatId
                          AND active = TRUE
                        """)
                .param("userId", userId)
                .param("chatId", chatId)
                .update();
    }

    @Override
    public long nextUpdateOffset() {
        return jdbc.sql("""
                        SELECT next_update_offset
                        FROM telegram_poll_cursor
                        WHERE cursor_key = 'PRIMARY'
                        """)
                .query(Long.class)
                .single();
    }

    @Override
    public void saveNextUpdateOffset(long offset) {
        jdbc.sql("""
                        UPDATE telegram_poll_cursor
                        SET next_update_offset = :offset, updated_at = CURRENT_TIMESTAMP
                        WHERE cursor_key = 'PRIMARY'
                        """)
                .param("offset", offset)
                .update();
    }
}
