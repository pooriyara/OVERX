// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class BridgeOptions {
    public String bridgeName;
    public int mtu;
    public String inet4Port;
    public String inet6Port;
    public String interfaceName;
    public int ruleIndex;
    public int routeTable;
}
