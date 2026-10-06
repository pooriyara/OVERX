// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class OutboundGroup {
    public String tag;
    public String type;
    public boolean selectable;
    public String selected;
    public boolean isExpand;
    /** Go: func (g *OutboundGroup) GetItems() OutboundGroupItemIterator */
    public OutboundGroupItemIterator getItems() { return null; }
}
