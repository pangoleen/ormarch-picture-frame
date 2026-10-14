// PF1007L: Firefox settings for 1 GB of memory (/usr/lib/firefox/browser/defaults/preferences/frame.js).
// Fewer processes: Firefox normally keeps up to 8 content processes and 3 spare ones.
// Trade-off: all web pages share the content processes (no site isolation).
pref("fission.webContentIsolationStrategy", 0);
pref("dom.ipc.processCount", 2);
pref("dom.ipc.processPrelaunch.fission.number", 0);
pref("dom.ipc.processPrelaunch.enabled", false);
pref("browser.tabs.remote.warmup.enabled", false);
// Less memory held for pages that are not on the screen.
pref("browser.sessionhistory.max_total_viewers", 1);
pref("browser.cache.memory.capacity", 32768);
pref("image.mem.surfacecache.max_size_kb", 65536);
pref("browser.tabs.unloadOnLowMemory", true);
// Fewer writes to the SD card.
pref("browser.cache.disk.enable", false);
pref("browser.sessionstore.interval", 60000);
// Quiet start.
pref("browser.aboutwelcome.enabled", false);
pref("browser.discovery.enabled", false);
pref("app.shield.optoutstudies.enabled", false);
// Video: this CPU decodes H.264 in software up to about 480p. AV1 and VP9 are too heavy.
pref("media.av1.enabled", false);
pref("media.mediasource.vp9.enabled", false);
// E076: one page used about 470 MB in three processes. The new-tab page runs in its own
// "Privileged Content" process (about 120 MB) and the built-in extensions in another (about 90 MB).
pref("browser.startup.homepage", "about:blank");
pref("browser.startup.page", 0);
pref("browser.newtabpage.enabled", false);
pref("browser.newtab.preload", false);
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("extensions.webextensions.remote", false);
pref("extensions.pocket.enabled", false);
pref("extensions.formautofill.addresses.enabled", false);
pref("extensions.formautofill.creditCards.enabled", false);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
pref("browser.ml.enable", false);
pref("browser.ml.chat.enabled", false);
