// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

public final class Connection {
    public String id;
    public String inbound;
    public String inboundType;
    public int ipVersion;
    public String network;
    public String source;
    public String destination;
    public String domain;
    public String protocol;
    public String user;
    public String fromOutbound;
    public long createdAt;
    public long closedAt;
    public long uplink;
    public long downlink;
    public long uplinkTotal;
    public long downlinkTotal;
    public String rule;
    public String outbound;
    public String outboundType;
    public ProcessInfo processInfo;
    public String displayDestination() { return null; }
}
