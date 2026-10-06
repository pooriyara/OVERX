// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class OutboundGroupItem {
    public String tag;
    public String type;
    private long uRLTestTime;
    private int uRLTestDelay;
    // gobind نامِ فیلدِ Go را دست‌نخورده می‌گذارد ⇒ URL با حروفِ بزرگ
    public long getURLTestTime() { return uRLTestTime; }
    public int getURLTestDelay() { return uRLTestDelay; }
    public void setURLTestTime(long v) { uRLTestTime = v; }
    public void setURLTestDelay(int v) { uRLTestDelay = v; }
}
