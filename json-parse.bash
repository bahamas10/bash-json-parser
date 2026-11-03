#
# JSON Parser in pure bash
#
# Exposes a `json-parse` function that will read a JSON string given on stdin
# and sets a global variable JSONREPLY with the parsed data.
#
# # Created
# Author: Dave Eddy <ysap@daveeddy.com>
# Date: October 24, 2026
# License: MIT
#
# # Contributors
# - Dave Eddy <ysap@daveeddy.com>

# ws = *(
# %x20 /              ; Space
# %x09 /              ; Horizontal tab
# %x0A /              ; Line feed or New line
# %x0D )              ; Carriage return
#
# move the _jp_idx pointer to the next char that is not whitespace, or to
# the end of the _jp_input
_jp-skip-whitespace() {
	local b c
	for (( ; _jp_idx < _jp_len; _jp_idx++)); do
		c=${_jp_input:_jp_idx:1}
		printf -v b '%d' "'$c"

		((
		    b == 0x20 ||
		    b == 0x09 ||
		    b == 0x0a ||
		    b == 0x0d
		)) || break
	done
}

# validate strings that bash supports (no nul support)
_jp-validate-utf8() {
	local s=$1

	# 0xxxxxxx                            1 byte,  7 bits
	# 110xxxxx 10xxxxxx                   2 bytes, 11 bits
	# 1110xxxx 10xxxxxx 10xxxxxx          3 bytes, 16 bits
	# 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx 4 bytes, 21 bits

	local LC_ALL=C
	local _jp_len=${#s}

	local i=0
	while ((i < _jp_len)); do
		local cp b1 b2 b3 b4 n

		# grab first byte
		printf -v b1 '%d' "'${s:i:1}"

		# check: b is 0xxxxxxx (1 octet)
		if (( (b1 & 2#10000000) == 0 )); then
			# 1 byte character, ASCII
			n=1

			# 0xxxxxxx
			cp=$(( b1 & 2#01111111 ))

		# check: b is 110xxxxx (2 octet)
		elif (( (b1 & 2#11100000) == 2#11000000 )); then
			# 2 byte character
			n=2

			(( i + 1 < _jp_len )) || return 1

			printf -v b2 '%d' "'${s:i+1:1}"

			(( (b2 & 2#11000000) == 2#10000000 )) || return 1

			# 110xxxxx 10xxxxxx
			cp=$((
				((b1 & 2#00011111) << 6) |
				 (b2 & 2#00111111)
			))

		# check: b is 1110xxxx (3 octet)
		elif (( (b1 & 2#11110000) == 2#11100000 )); then
			# 3 byte character
			n=3

			(( i + 2 < _jp_len )) || return 1

			printf -v b2 '%d' "'${s:i+1:1}"
			printf -v b3 '%d' "'${s:i+2:1}"

			(( (b2 & 2#11000000) == 2#10000000 )) || return 1
			(( (b3 & 2#11000000) == 2#10000000 )) || return 1

			# 1110xxxx 10xxxxxx 10xxxxxx
			cp=$((
				((b1 & 2#00001111) << 12) |
				((b2 & 2#00111111) << 6) |
				 (b3 & 2#00111111)
			))

		# check: b is 11110xxx (4 octet)
		elif (( (b1 & 2#11111000) == 2#11110000 )); then
			# 4 byte character
			n=4

			(( i + 3 < _jp_len )) || return 1

			printf -v b2 '%d' "'${s:i+1:1}"
			printf -v b3 '%d' "'${s:i+2:1}"
			printf -v b4 '%d' "'${s:i+3:1}"

			(( (b2 & 2#11000000) == 2#10000000 )) || return 1
			(( (b3 & 2#11000000) == 2#10000000 )) || return 1
			(( (b4 & 2#11000000) == 2#10000000 )) || return 1

			# 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
			cp=$((
				((b1 & 2#00000111) << 18) |
				((b2 & 2#00111111) << 12) |
				((b3 & 2#00111111) << 6) |
				 (b4 & 2#00111111)
			))
		else
			return 1
		fi
		(( i += n ))

		# at this point we have a codepoint and we've filtered out
		# invalid "looking" bytes, but we still have more work to do

		# check for overlong sequences
		case "$n" in
			1) ((cp >= 0x00000000 && cp <= 0x0000007F)) || return 1;;
			2) ((cp >= 0x00000080 && cp <= 0x000007FF)) || return 1;;
			3) ((cp >= 0x00000800 && cp <= 0x0000FFFF)) || return 1;;
			4) ((cp >= 0x00010000 && cp <= 0x0010FFFF)) || return 1;;
			*) exit 1;;
		esac

		# check for utf-16 surrogate pair domain
		# U+D800 and U+DFFF
		((cp >= 0xd800 && cp <= 0xdfff)) && return 1
	done

	return 0
}

_jp-parse-object() {
	# " {"foo": "bar" } "
	#   |
	#  _jp_idx
	local c=${_jp_input:_jp_idx:1}
	if [[ $c != '{' ]]; then
		_jp-error 'internal failed parse object'
		return 1
	fi
	((_jp_idx++))

	_jp-skip-whitespace

	declare -Ag JSONREPLY=()

	local c=${_jp_input:_jp_idx:1}
	if [[ $c == '}' ]]; then
		((_jp_idx++))
		return 0
	fi

	local key value typ
	while true; do
		# get the key
		_jp-skip-whitespace
		key=${| _jp-parse-string; } || return 1
		if [[ $key == '' ]]; then
			_jp-error 'object cannot contain empty key'
			return 1
		fi
		_jp-skip-whitespace

		c=${_jp_input:_jp_idx:1}
		if [[ $c != ':' ]]; then
			_jp-error 'colon must separate object keys from values'
			return 1
		fi
		((_jp_idx++))

		_jp-skip-whitespace

		# get the value
		if [[ -z $typ ]]; then
			# peek the first value and determine type
			c=${_jp_input:_jp_idx:1}
			case "$c" in
				[0-9] | '-')
					typ='number'
					declare -Agi JSONREPLY
					;;
				'"') typ='string';;
				't' | 'f') typ='boolean';;
				*)
					_jp-error 'objects can only contain numbers or strings or booleans'
					return 1
					;;
			esac
		fi
		case "$typ" in
			number)  value=${| _jp-parse-number;  } || return 1;;
			string)  value=${| _jp-parse-string;  } || return 1;;
			boolean) value=${| _jp-parse-boolean; } || return 1;;
			*) exit 1;;
		esac

		_jp-skip-whitespace

		JSONREPLY[$key]=$value

		c=${_jp_input:_jp_idx:1}
		((_jp_idx++))

		case "$c" in
			',') continue;;
			'}') break;;
			*)
				_jp-error "unexpected token in object: ${c@Q}"
				return 1
		esac
	done

	return 0
}

_jp-parse-array() {
	# " [1,2,3]"
	#   |
	#  _jp_idx
	local c=${_jp_input:_jp_idx:1}
	if [[ $c != '[' ]]; then
		_jp-error 'internal failed parse array'
		return 1
	fi
	((_jp_idx++))

	_jp-skip-whitespace

	declare -ag JSONREPLY=()

	local c=${_jp_input:_jp_idx:1}
	if [[ $c == ']' ]]; then
		((_jp_idx++))
		return 0
	fi

	# peek the first value and determine type
	local typ
	case "$c" in
		[0-9] | '-') typ='number';;
		'"') typ='string';;
		't' | 'f') typ='boolean';;
		*)
			_jp-error 'arrays can only contain numbers or strings or booleans'
			return 1
			;;
	esac

	local value
	while true; do
		_jp-skip-whitespace
		case "$typ" in
			number)  value=${| _jp-parse-number;  } || return 1;;
			string)  value=${| _jp-parse-string;  } || return 1;;
			boolean) value=${| _jp-parse-boolean; } || return 1;;
			*) exit 1;;
		esac
		_jp-skip-whitespace

		JSONREPLY+=("$value")

		c=${_jp_input:_jp_idx:1}
		((_jp_idx++))

		case "$c" in
			',') continue;;
			']') break;;
			*)
				_jp-error "unexpected token in array: ${c@Q}"
				return 1
		esac
	done

	return 0
}

_jp-parse-unicode-string() {
	# %x75 4HEXDIG )  ; uXXXX                U+XXXX

	# "\u1234"
	#   |
	#  _jp_idx
	local c=${_jp_input:_jp_idx:1}
	if [[ $c != 'u' ]]; then
		_jp-error 'internal failed unicode string'
		return 1
	fi

	local cp=${_jp_input:_jp_idx+1:4}
	local re='^[a-fA-F0-9]{4}$'

	# validate the code point we see
	if ! [[ $cp =~ $re ]]; then
		_jp-error "invalid unicode code point: ${cp@Q}"
		return 1
	fi

	((_jp_idx += 4))

	# turn the code-point hex string into an actual number
	cp=$((16#$cp))

	# check for surrogate pair
	if ((0xD800 <= cp && cp <= 0xDBFF)); then
		local high_cp=$cp
		local low_cp

		# we have a surrogate pair - get the trailing code point now
		local s=${_jp_input:_jp_idx+1:2}

		if [[ $s != '\u' ]]; then
			_jp-error "invalid surrogate pair: $s"
			return 1
		fi

		((_jp_idx += 2))
		low_cp=${_jp_input:_jp_idx+1:4}

		# validate the code point we see
		if ! [[ $low_cp =~ $re ]]; then
			_jp-error "invalid unicode code point: ${low_cp@Q}"
			return 1
		fi

		((_jp_idx += 4))

		low_cp=$((16#$low_cp))
		if ! ((0xDC00 <= low_cp && low_cp <= 0xDFFF)); then
			_jp-error "invalid unicode surrogate pair low code point: ${low_cp@Q}"
			return 1
		fi

		((cp = 0x10000))
		((cp += (high_cp & 0x03FF) << 10))
		((cp += (low_cp & 0x03FF) ))
	fi

	# turn the unicode codepoint into its char
	local out hex
	printf -v hex '%08x' "$cp"
	printf -v out "\\U$hex"

	REPLY=$out
}

# "foo\rbar"
_jp-parse-special-string() {
	# optionally process the special char
	# %x22 /          ; "    quotation mark  U+0022
	# %x5C /          ; \    reverse solidus U+005C
	# %x2F /          ; /    solidus         U+002F
	# %x62 /          ; b    backspace       U+0008
	# %x66 /          ; f    form feed       U+000C
	# %x6E /          ; n    line feed       U+000A
	# %x72 /          ; r    carriage return U+000D
	# %x74 /          ; t    tab             U+0009
	# %x75 4HEXDIG )  ; uXXXX                U+XXXX

	local c=${_jp_input:_jp_idx:1}
	local out
	case "$c" in
		'"') out='"';;
		'\') out='\';;
		'/') out='/';;
		'b') out=$'\b';;
		'f') out=$'\f';;
		'n') out=$'\n';;
		'r') out=$'\r';;
		't') out=$'\t';;
		'u')
			out=${| _jp-parse-unicode-string; } || return 1
			;;
		*)
			_jp-error "unknown escape char: ${c@Q}"
			return 1
			;;
	esac

	REPLY=$out
}

# parse a string starting at the first '"' character
_jp-parse-string() {
	local s=''
	local c

	c=${_jp_input:_jp_idx:1}
	if [[ $c != '"' ]]; then
		_jp-error '_jp-parse-string called with non-string'
		return 1
	fi

	((_jp_idx++))

	# user gave us an empty string
	c=${_jp_input:_jp_idx:1}
	if [[ $c == '"' ]]; then
		((_jp_idx++))
		printf ''
		return 0
	fi

	# user gave us a NON empty string lol
	local closed='false'
	for (( ; _jp_idx < _jp_len; _jp_idx++)); do
		c=${_jp_input:_jp_idx:1}
		#printf -v b '%d' "'$c"

		case "$c" in
			'\')
				((_jp_idx++))
				c=${| _jp-parse-special-string; } || return 1
				s+=$c
				;;
			'"')
				((_jp_idx++))
				closed='true'
				break
				;;
			*) s+=$c;;
		esac
	done

	if ! $closed; then
		_jp-error 'string opens but never closes'
		return 1
	fi

	REPLY=$s
}

# parse a number, positive or negative integers only.
# "-0" is allowed, no exponents or fraction values are
# permitted.  no leading zeroes allowed.
_jp-parse-number() {
	# ex: "12345", num=1, _jp_idx -> 2
	local c=${_jp_input:_jp_idx:1}
	local num=$c

	if [[ $num != [0-9-] ]]; then
		_jp-error 'invalid number given to _jp-parse-number'
		return 1
	fi

	((_jp_idx++))

	for (( ; _jp_idx < _jp_len; _jp_idx++)); do
		c=${_jp_input:_jp_idx:1}
		#printf -v b '%d' "'$c"

		case "$c" in
			[0-9]) num+=$c;;
			[eE.])
				_jp-error "number unsupported"
				return 1
				;;
			*) break;;
		esac
	done

	# got *something* like a number - validate it
	if [[ $num == '-' ]]; then
		_jp-error 'invalid number - only "-" found'
		return 1
	fi

	# don't allow leading zeroes
	if [[ $num == '0' || $num == '-0' ]]; then
		:
	elif [[ $num == 0* || $num == -0* ]]; then
		_jp-error 'leading zeroes found in number'
		return 1
	fi

	# check for overflow
	local parsed
	if ! printf -v parsed '%d' "$num"; then
		_jp-error "invalid number given: $num"
		return 1
	fi

	REPLY=$parsed
}

# parses the json values 'true' and 'false' into 
# safely executable string values in Bash
_jp-parse-boolean() {
	local s=${_jp_input:_jp_idx:4}
	if [[ $s == 'true' ]]; then
		((_jp_idx+=4))
		REPLY="builtin true"
		return 0
	fi

	local s=${_jp_input:_jp_idx:5}
	if [[ $s == 'false' ]]; then
		((_jp_idx+=5))
		REPLY="builtin false"
		return 0
	fi

	_jp-error "'$s' is given to _jp-parse-boolean"
	return 1


}


_jp-debug() {
	local msg=$*
	local lhs=${_jp_input:0:_jp_idx}
	local c=${_jp_input:_jp_idx:1}
	local rhs=${_jp_input:_jp_idx+1}

	rhs=${rhs//$'\n'}
	c=${c//$'\n'/ }
	lhs=${lhs//$'\n'}

	c=$'\e[42m\e[1m'$c$'\e[0m'

	local i
	printf -v i '%4d' "$_jp_idx"

	echo "(_jp_idx $i): $lhs$c$rhs $msg" >&2
}

_jp-error() {
	echo "[json-parse] error at offset $_jp_idx: $*" >&2
}

# take JSON data from stdin, parse it, and return the variable that is set
json-parse() {
	unset JSONREPLY

	local LC_ALL=C.UTF-8
	local _jp_idx=0
	local _jp_len=0
	local _jp_input=''

	# read the data into a string
	IFS= read -r -d '' _jp_input

	# validate it as UTF-8
	if ! _jp-validate-utf8 "$_jp_input"; then
		_jp-error '_jp_input must be UTF8'
		return 1
	fi

	# actually start doing some json parsing
	_jp_idx=0
	_jp_len=${#_jp_input}

	# first things first, skip any whitespace
	_jp-skip-whitespace

	# parse the value seen
	local b c
	c=${_jp_input:_jp_idx:1}
	printf -v b '%d' "'$c"

	case "$c" in
		'"')
			local s
			s=${| _jp-parse-string; } || return 1
			declare -g JSONREPLY
			JSONREPLY=$s
			;;
		[0-9] | '-')
			local num
			num=${| _jp-parse-number; } || return 1
			declare -gi JSONREPLY
			JSONREPLY=$num
			;;
		'[')
			_jp-parse-array || return 1
			;;
		'{')
			_jp-parse-object || return 1
			;;
		't' | 'f')
			local value
			value=${| _jp-parse-boolean; } || return 1
			declare -g JSONREPLY
			JSONREPLY=$value
			;;
		'n')
			_jp-error 'null/true/false unsupported'
			return 1
			;;
		*)
			_jp-error "unknown json value: $c"
			return 1
			;;
	esac

	_jp-skip-whitespace

	# we are done parsing, ensure things look right
	if ((_jp_idx != _jp_len)); then
		_jp-error 'internal inconsistency - allinput not consumed'
		return 1
	fi

	return 0
}

if ! (return 0 &>/dev/null); then
	json-parse "$@" || exit 1
	declare -p JSONREPLY
fi
