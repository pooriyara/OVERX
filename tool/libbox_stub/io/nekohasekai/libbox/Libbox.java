// استابِ libbox — فقط برای کامپایل (جزئیات در ../STUBS.md)
// تولیدشده بر اساس sing-box v1.14.2 / experimental/libbox + قواعدِ gobind.
// فیلدها عمومی‌اند چون در کلاسِ تولیدشده‌ی جاوا هم «پلتفرم‌تایپ» دارند.
package io.nekohasekai.libbox;

/** کلاسِ بسته: ثابت‌ها و کارخانه‌ها (command.go / setup.go / platform.go) */
public final class Libbox {
    // sing-tun: DNSModeDisabled = "disabled" → رشته است، نه عدد
    public static final String DNSModeDisabled = "disabled";
    public static final String DNSModeNative = "native";
    public static final String DNSModeHijack = "hijack";
    public static final int InterfaceTypeWIFI = 1;
    public static final int InterfaceTypeCellular = 2;
    public static final int InterfaceTypeEthernet = 4;
    public static final int InterfaceTypeOther = 0;
    public static final int CommandLog = 0;
    public static final int CommandStatus = 1;
    public static final int CommandGroup = 2;
    public static final int CommandClashMode = 3;
    public static final int CommandConnections = 4;
    public static final int CommandOutbounds = 5;

    public static void setup(SetupOptions options) throws Exception { }
    public static void setLocale(String localeID) throws Exception { }
    public static String version() { return ""; }
    public static CommandClient newCommandClient(CommandClientHandler handler,
        CommandClientOptions options) { return new CommandClient(); }
    public static Connections newConnections() { return new Connections(); }
}
