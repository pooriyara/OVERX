// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

/** command_server.go */
public interface CommandServerHandler {
    void serviceStop();
    void serviceReload();
    SystemProxyStatus getSystemProxyStatus();
    void setSystemProxyEnabled(boolean enabled);
    void triggerNativeCrash();
    void writeDebugMessage(String message);
    int connectSSHAgent();
}
