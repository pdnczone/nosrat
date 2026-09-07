// Package config includes a tiny, dependency-free YAML-subset parser.
//
// We deliberately avoid pulling in gopkg.in/yaml.v3 (or any module) so that
// nosrat builds as a single static binary with `go build` and no network
// access to a module proxy is ever required on the target VPS. The subset
// supported is exactly what a nosrat config needs:
//
//   - nested mappings via 2-space indentation
//   - scalar values (strings, ints, bools) - quotes optional
//   - lists of scalars or lists of mappings using "- " items
//   - comments starting with '#' (unless inside a quoted string)
//   - blank lines ignored
//
// It is NOT a general purpose YAML parser and will reject anything outside
// this subset with a clear error rather than silently misparsing.
package config

import (
	"fmt"
	"strconv"
	"strings"
)

// yNode is either a map[string]any, []any, or a scalar (string/bool/int/float64).
type yNode = any

func parseYAMLLite(data []byte) (map[string]any, error) {
	lines := strings.Split(string(data), "\n")

	type rawLine struct {
		indent int
		text   string
		lineNo int
	}

	var raw []rawLine
	for i, l := range lines {
		trimmedRight := strings.TrimRight(l, " \t\r")
		if strings.TrimSpace(trimmedRight) == "" {
			continue
		}
		content := stripComment(trimmedRight)
		if strings.TrimSpace(content) == "" {
			continue
		}
		indent := 0
		for indent < len(content) && content[indent] == ' ' {
			indent++
		}
		raw = append(raw, rawLine{indent: indent, text: content[indent:], lineNo: i + 1})
	}

	pos := 0

	var parseBlock func(minIndent int) (any, error)

	parseScalar := func(s string) any {
		s = strings.TrimSpace(s)
		if len(s) >= 2 && ((s[0] == '"' && s[len(s)-1] == '"') || (s[0] == '\'' && s[len(s)-1] == '\'')) {
			return s[1 : len(s)-1]
		}
		switch strings.ToLower(s) {
		case "true":
			return true
		case "false":
			return false
		case "null", "~", "":
			return nil
		}
		if i, err := strconv.Atoi(s); err == nil {
			return i
		}
		if f, err := strconv.ParseFloat(s, 64); err == nil {
			return f
		}
		return s
	}

	parseBlock = func(minIndent int) (any, error) {
		if pos >= len(raw) {
			return map[string]any{}, nil
		}

		firstIndent := raw[pos].indent
		if firstIndent < minIndent {
			return map[string]any{}, nil
		}

		if strings.HasPrefix(raw[pos].text, "- ") || raw[pos].text == "-" {
			var list []any
			for pos < len(raw) && raw[pos].indent == firstIndent &&
				(strings.HasPrefix(raw[pos].text, "- ") || raw[pos].text == "-") {
				itemText := strings.TrimPrefix(raw[pos].text, "-")
				itemText = strings.TrimPrefix(itemText, " ")
				lineNo := raw[pos].lineNo
				if strings.Contains(itemText, ":") && !isQuoted(itemText) {
					// inline map item, e.g. "- to: 10.0.0.0/24"
					k, v, ok := splitKV(itemText)
					if !ok {
						return nil, fmt.Errorf("line %d: malformed list-map item %q", lineNo, itemText)
					}
					m := map[string]any{}
					if v == "" {
						pos++
						sub, err := parseBlock(firstIndent + 2)
						if err != nil {
							return nil, err
						}
						m[k] = sub
					} else {
						m[k] = parseScalar(v)
						pos++
					}
					// consume any further indented keys belonging to same list item
					for pos < len(raw) && raw[pos].indent > firstIndent {
						k2, v2, ok := splitKV(raw[pos].text)
						if !ok {
							return nil, fmt.Errorf("line %d: expected key: value", raw[pos].lineNo)
						}
						if v2 == "" {
							pos++
							sub, err := parseBlock(raw[pos-1].indent + 2)
							if err != nil {
								return nil, err
							}
							m[k2] = sub
						} else {
							m[k2] = parseScalar(v2)
							pos++
						}
					}
					list = append(list, m)
				} else if itemText == "" {
					pos++
					sub, err := parseBlock(firstIndent + 2)
					if err != nil {
						return nil, err
					}
					list = append(list, sub)
				} else {
					list = append(list, parseScalar(itemText))
					pos++
				}
			}
			return list, nil
		}

		m := map[string]any{}
		for pos < len(raw) && raw[pos].indent == firstIndent {
			k, v, ok := splitKV(raw[pos].text)
			if !ok {
				return nil, fmt.Errorf("line %d: expected 'key: value', got %q", raw[pos].lineNo, raw[pos].text)
			}
			pos++
			if v == "" {
				sub, err := parseBlock(firstIndent + 1)
				if err != nil {
					return nil, err
				}
				m[k] = sub
			} else {
				m[k] = parseScalar(v)
			}
		}
		return m, nil
	}

	result, err := parseBlock(0)
	if err != nil {
		return nil, err
	}
	m, ok := result.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("top-level document must be a mapping")
	}
	return m, nil
}

func isQuoted(s string) bool {
	s = strings.TrimSpace(s)
	return len(s) >= 2 && (s[0] == '"' || s[0] == '\'')
}

func stripComment(s string) string {
	inQuote := byte(0)
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inQuote != 0 {
			if c == inQuote {
				inQuote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			inQuote = c
			continue
		}
		if c == '#' {
			return s[:i]
		}
	}
	return s
}

func splitKV(s string) (key, val string, ok bool) {
	idx := -1
	inQuote := byte(0)
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inQuote != 0 {
			if c == inQuote {
				inQuote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			inQuote = c
			continue
		}
		if c == ':' && (i+1 == len(s) || s[i+1] == ' ') {
			idx = i
			break
		}
	}
	if idx == -1 {
		return "", "", false
	}
	key = strings.TrimSpace(s[:idx])
	val = strings.TrimSpace(s[idx+1:])
	return key, val, true
}

// helpers used by config.go to walk the generic map safely.

func getMap(m map[string]any, key string) map[string]any {
	if v, ok := m[key]; ok {
		if mm, ok := v.(map[string]any); ok {
			return mm
		}
	}
	return map[string]any{}
}

func getList(m map[string]any, key string) []any {
	if v, ok := m[key]; ok {
		if l, ok := v.([]any); ok {
			return l
		}
	}
	return nil
}

func getString(m map[string]any, key, def string) string {
	if v, ok := m[key]; ok && v != nil {
		return fmt.Sprintf("%v", v)
	}
	return def
}

func getInt(m map[string]any, key string, def int) int {
	if v, ok := m[key]; ok {
		switch t := v.(type) {
		case int:
			return t
		case float64:
			return int(t)
		}
	}
	return def
}

func getBool(m map[string]any, key string, def bool) bool {
	if v, ok := m[key]; ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return def
}
