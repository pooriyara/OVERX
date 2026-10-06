// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

/** platform.go — ۲۷ متد */
public interface PlatformInterface {
    LocalDNSTransport localDNSTransport();
    boolean usePlatformAutoDetectInterfaceControl();
    void autoDetectInterfaceControl(int fd);
    int openTun(TunOptions options);
    boolean useProcFS();
    ConnectionOwner findConnectionOwner(int ipProtocol, String sourceAddress,
        int sourcePort, String destinationAddress, int destinationPort);
    void startDefaultInterfaceMonitor(InterfaceUpdateListener listener);
    void closeDefaultInterfaceMonitor(InterfaceUpdateListener listener);
    NetworkInterfaceIterator getInterfaces();
    boolean underNetworkExtension();
    boolean includeAllNetworks();
    WIFIState readWIFIState();
    void clearDNSCache();
    void sendNotification(Notification notification);
    void cancelNotification(String identifier, int typeID);
    void startNeighborMonitor(NeighborUpdateListener listener);
    void closeNeighborMonitor(NeighborUpdateListener listener);
    void registerMyInterface(String name);
    boolean usePlatformShell();
    void checkPlatformShell();
    ShellSession openShellSession(PlatformUser user, String command,
        StringIterator environ, String term, int rows, int cols);
    PlatformUser lookupUser(String username);
    String lookupSFTPServer();
    String readSystemSSHHostKey();
    String tailscaleHostname();
    boolean usePlatformBridge();
    BridgeSession createBridge(BridgeOptions options);
}
