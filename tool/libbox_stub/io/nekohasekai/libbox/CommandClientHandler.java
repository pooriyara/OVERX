// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

/** command_client.go */
public interface CommandClientHandler {
    void connected();
    void disconnected(String message);
    void setDefaultLogLevel(int level);
    void clearLogs();
    void writeLogs(LogIterator messageList);
    void writeStatus(StatusMessage message);
    void writeGroups(OutboundGroupIterator message);
    void writeOutbounds(OutboundGroupItemIterator message);
    void initializeClashMode(StringIterator modeList, String currentMode);
    void updateClashMode(String newMode);
    void writeConnectionEvents(ConnectionEvents events);
}
