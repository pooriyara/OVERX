// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

/** tun.go */
public interface TunOptions {
    RoutePrefixIterator getInet4Address();
    RoutePrefixIterator getInet6Address();
    StringBox getDNSMode();
    StringIterator getDNSServerAddress();
    int getMTU();
    boolean getAutoRoute();
    boolean getStrictRoute();
    RoutePrefixIterator getInet4RouteAddress();
    RoutePrefixIterator getInet6RouteAddress();
    RoutePrefixIterator getInet4RouteExcludeAddress();
    RoutePrefixIterator getInet6RouteExcludeAddress();
    RoutePrefixIterator getInet4RouteRange();
    RoutePrefixIterator getInet6RouteRange();
    StringIterator getIncludePackage();
    StringIterator getExcludePackage();
    boolean isHTTPProxyEnabled();
    String getHTTPProxyServer();
    int getHTTPProxyServerPort();
    StringIterator getHTTPProxyBypassDomain();
    StringIterator getHTTPProxyMatchDomain();
}
