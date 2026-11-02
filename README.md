Bash Json Parser
================

JSON Parser in pure bash

Exposes a `json-parse` function that will read a JSON string given on stdin
and sets a global variable JSONREPLY with the parsed data.

Usage
-----

```bash
json-parse <<< '{"foo":"bar"}' || exit 1
echo "${JSONREPLY[foo]}"
# => "bar"
```

YouTube
-------

Watch me build this live on YouTube.

<a href="https://youtu.be/iIUH4JSJTAw"><img
alt="Bash json parser YouTube Thumbnail"
src="https://i.ytimg.com/vi/iIUH4JSJTAw/maxresdefault.jpg"
/></a>

License
-------

MIT License
