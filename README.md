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

json-parse <<< 'true' || exit 1
echo $JSONREPLY
# => "builtin true"

json-parse <<< '{"foo":true}' || exit 1
if ${JSONREPLY[foo]}; then
    echo success
else
    echo failed
fi
# => "success"

json-parse <<< '{"foo":false}' || exit 1
if ${JSONREPLY[foo]}; then
    echo success
else
    echo failed
fi
# => "failed"

json-parse <<< '[true,false]' || exit 1
if ${JSONREPLY[0]}; then
    echo success
else
    echo failed
fi
# => success
if ${JSONREPLY[1]}; then
    echo success
else
    echo failed
fi
# => failed
```

License
-------

MIT License
