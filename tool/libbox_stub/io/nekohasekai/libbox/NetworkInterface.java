// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class NetworkInterface {
    public int index;
    public int mtu;
    public String name;
    public StringIterator addresses;
    public int flags;
    public int type;
    public StringIterator dnsServer;
    public StringIterator gateway;
    public boolean metered;
}
