// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class CommandClient {
    public void connect() throws Exception { }
    public void disconnect() throws Exception { }
    public void selectOutbound(String groupTag, String outboundTag) throws Exception { }
    public void urlTest(String outboundTag) throws Exception { }
    public void closeConnection(String connId) throws Exception { }
    public void closeConnections() throws Exception { }
}
