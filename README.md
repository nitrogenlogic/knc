# knc

The Kinematic Network Controller from Nitrogen Logic's [Depth Camera
Controller][0].  KNC provides a browser-based user interface for defining zones,
connecting to Hue lights, setting up presence-based triggers on lights, and
configuring the controller.  In other words, KNC provides the UI frontend for
the [KND][3] backend.  KNC also provides xAP protocol compatibility for
integration with Homeseer and similar DIY automation software.

KNC is written in Ruby with EventMachine.  This makes it faster than e.g.
Sinatra, especially on the limited hardware of the SheevaPlug that Nitrogen
Logic controllers were based on, but the code is not a shining example of how to
write HTTP services in Ruby.  Lots of things would be done very differently
today.

This repo also has scripts for building firmware update files in the .nlfw
format.  See `mk_firmware.sh` and `do_firmware` from [nlutils][2].  Those
scripts were written for Debian Squeeze, and are broken now because of changes
in Debian and the web (SystemD, TLS1.2+, etc.).  Most of the stuff under
`embedded/` is related to firmware updates or to controller diagnostics, and
won't work now that Debian Squeeze is long, long obsolete.

I've added [a few notes about this project on my blog][4].

# Copying

&copy; 2011-2021 Mike Bourgeous, licensed under [GNU Affero GPLv3][1].

Some CSS and Javascript dependencies under `wwwdata/` will have their own
licenses.  See each file for details.

Use of knc code in new projects is not recommended due in part to its older
style and obsolete dependencies.

# Running

## Dependencies

You'll want Ruby, plus [nlutils][2], and [knd][3].

```bash
rvm install 2.7.2
echo '2.7.2' > .ruby-version
echo 'knc' > .ruby-gemset
rvm use .
```

## Direct use

You can run KNC directly:

```bash
bundle install
KNC_SAVEDIR=/var/tmp/ ./knc.rb
```

Then load http://localhost:8089/ in your browser.

## Building a .deb package that uses system ruby

The .deb package won't enable itself in SystemD (yet).

```bash
meta/make_pkg.sh
```

## Cross-compiling as a .deb for ARM

This probably won't work fully, but with some stubbornness and patience and
reading the source code you might be able to get .deb packages cross-compiled.

Nitrogen Logic controllers originally used Debian Squeeze and a somewhat
automated build process, but significant changes to the Linux and web ecosystem
over the last 10 years (such as SystemD and TLS1.2+) have broken most of that
build process.

```bash
# From nlutils
# Using make_root first is a hack to get nlutils installed into the build
# chroot knc will use.  A better long-term option if this code were to be
# resurrected for a new product would be making everything a Debian package,
# using Docker containers for building, and/or 100% buying into some other
# embedded Linux ecosystem for build tooling.
PACKAGE=0 TESTS=0 meta/make_root.sh

# From here in knc
meta/cross_build.sh
```

[0]: http://www.nitrogenlogic.com/products/depth_controller.html
[1]: https://www.gnu.org/licenses/agpl-3.0.html
[2]: https://github.com/nitrogenlogic/nlutils
[3]: https://github.com/nitrogenlogic/knd
[4]: https://blog.mikebourgeous.com/2021/03/09/opening-knc/
