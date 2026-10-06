// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

/** Go: func NewWIFIState(wifiSSID, wifiBSSID string) *WIFIState ⇒ سازنده */
public final class WIFIState {
    public String ssid;
    public String bssid;
    public WIFIState(String ssid, String bssid) { this.ssid = ssid; this.bssid = bssid; }
    public WIFIState() { this("", ""); }
}
