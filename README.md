# aircap

An Omarchy bar widget for one-click monitor-mode Wi-Fi captures, in the spirit
of [Airtool](https://www.intuitibits.com/products/airtool/) on macOS.

- Pick a band, channel, and width (20/40/80/160/320 MHz, 2.4 GHz HT40±). Only
  channels your regulatory domain enables are listed, and a width is offered
  only when every 20 MHz subchannel in its block is enabled. DFS and 6 GHz PSC
  channels are marked.
- **Use current** tunes to the channel and width you're associated on.
- While capturing, the bar shows a live packet count; the panel adds elapsed
  time, rate, and file size.
- Captures are saved as `~/Captures/aircap_<band>-ch<N>-<width>MHz_<time>.pcapng`
  and can open in Wireshark as soon as you stop.

| Bar input    | Action                     |
| ------------ | -------------------------- |
| Click        | Open the panel             |
| Right-click  | Start / stop a capture     |
| Middle-click | Open the latest capture    |

Panel keys: `Enter` start/stop · `c` current channel · `2`/`5`/`6` band ·
`w` open latest capture · `f` open captures folder.

IPC: `omarchy-shell jwil007.aircap start|stop|toggleCapture|restore|status`.

## How it works

Monitor mode needs root, so **Set up** (one-time, in a terminal) installs
Wireshark if needed, a root-owned copy of `bin/aircap-helper` at
`/usr/local/libexec/aircap/aircap-helper`, and `/etc/sudoers.d/aircap` allowing
`%wheel` to run that one helper without a password. The helper takes no paths:
dumpcap writes the capture to stdout and the unprivileged wrapper redirects it
into a file you own.

For a capture, the helper:

1. stops `roamctl@<iface>` if it's running, and takes the interface away from
   NetworkManager (`managed no`) or stops iwd;
2. switches the interface to monitor mode and tunes it with
   `iw dev <iface> set freq <control> <width> <center1>`;
3. runs `dumpcap` until you stop it;
4. switches back to managed mode and hands the interface back to whoever had
   it (NetworkManager reconnects; roamctl restarts).

Wi-Fi is disconnected for the duration of the capture, as with Airtool. If a
capture dies without cleaning up (e.g. the machine sleeps mid-capture), the
panel offers **Restore Wi-Fi**.

When the plugin's helper changes, the panel asks you to run Set up again so the
installed copy matches.

## Settings

| Setting                       | Default      |
| ----------------------------- | ------------ |
| Wireless interface            | first found  |
| Save captures to              | `~/Captures` |
| Open in Wireshark when done   | on           |
| Snap length (0 = whole frame) | 0            |

## Uninstall

```
~/.config/omarchy/plugins/jwil007.aircap/bin/aircap uninstall
omarchy plugin remove jwil007.aircap
```

This removes the helper and sudoers rule; Wireshark and your captures stay.
