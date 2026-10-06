// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class CommandServer {
    /** Go: NewCommandServer(handler, platformInterface) (*CommandServer, error) */
    public CommandServer(CommandServerHandler handler, PlatformInterface platformInterface) { }
    public void start() throws Exception { }
    public void startOrReloadService(String configContent, OverrideOptions options) throws Exception { }
    public void closeService() throws Exception { }
    public void close() throws Exception { }
}
