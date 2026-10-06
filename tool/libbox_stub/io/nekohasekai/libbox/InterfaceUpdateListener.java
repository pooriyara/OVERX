// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public interface InterfaceUpdateListener {
    void updateDefaultInterface(String interfaceName, int interfaceIndex,
        boolean isExpensive, boolean isConstrained);
    void updateNetworkPath(String networkPath);
}
