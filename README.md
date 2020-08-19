# releng-misc

<!-- vim-markdown-toc GFM -->

* [Overview](#overview)
* [Bolt tasks](#bolt-tasks)
* [Contributing](#contributing)

<!-- vim-markdown-toc -->

## Overview

The goal of this project is to collect the various tools (script, config,
notes, etc.) we've been using to assist with RELENG-related activities.
The purpose is to establish **awareness** of these tools.

**WARNING** Things collected here may be broken, full of bugs, hard to use, and
out-of-date.   Don't assume that anything here is suitable to use in
production without inspecting and testing it first.


## Bolt tasks

Some scripts are packaged as [Puppet Bolt] tasks (in the [Boltdir/](Boltdir/)
directory). For information on the available tasks, run:

```sh
bolt task show [task_name]
```

You will need at least Bolt 2.8.0 (possibly higher) to do this.


## Contributing

* If you'd like to contribute something that you've been using, drop it in a
  new folder (preferably with a small `README.md` to let  others know what it
  is). Don't let polishing things hold you up from contributing!

[bolt]: https://puppet.com/docs/bolt/latest/bolt.html
