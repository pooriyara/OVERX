// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class SetupOptions {
    public String basePath;
    public String workingPath;
    public String tempPath;
    public boolean fixAndroidStack;
    public int commandServerListenPort;
    public String commandServerSecret;
    /** Go: LogMaxLines int → در جاوا long */
    public long logMaxLines;
    public boolean debug;
    public String crashReportSource;
    public String appVersion;
    public String appMarketingVersion;
    public boolean oomKillerEnabled;
    public boolean oomKillerDisabled;
    public long oomMemoryLimit;
    public boolean powerReportEnabled;
}
