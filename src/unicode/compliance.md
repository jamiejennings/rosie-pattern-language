# Compliance to Unicode standards


## Unicode Regular Expressions

[Unicode Regular Expressions](http://unicode.org/reports/tr18/)

### Compliance level 0

Compliance is being measured using version 19 of the compliance report:
http://www.unicode.org/reports/tr18/tr18-19.html

### Compliance level 1

#### RL1.1 Hex Notation

Met using `\uNNNN` (4 hex digits) and `\UNNNNNNNN` (8 hex digits).

#### RL1.2 Properties

- General Category

The following are MISSING:
- Strongly recommended that both property abbreviations and full names are supported
- Script -- see `Scripts.txt` for codepoints mapped to their script property 
- Script extensions? -- see `ScriptExtensions.txt` 
- White_Space -- defined in http://www.unicode.org/Public/UCD/latest/ucd/PropList.txt 
- Other* (needed below) -- defined in http://www.unicode.org/Public/UCD/latest/ucd/PropList.txt 
- Alphabetic -- Generated from: Lowercase + Uppercase + Lt + Lm + Lo + Nl + Other_Alphabetic
- Uppercase -- Generated from: Lu + Other_Uppercase
- Lowercase -- Generated from: Ll + Other_Lowercase
- Noncharacter codepoint -- The set of 66 codepoints assigned "Cn"
- Default\_Ignorable codepoint -- Generated from Other\_Default\_Ignorable\_Code_Point
    - + Cf (format characters)
    - + Variation_Selector
    - - White_Space
    - - FFF9..FFFB (annotation characters)
    - - 0600..0605, 06DD, 070F, 08E2, 110BD (exceptional Cf characters that should be visible)
- Any -- \u0000 through \U0010FFFF
- ASCII -- \u0000 through \u007F
- ASSIGNED -- defined as Any - UNASSIGNED - Cn


**The following are beyond the RL1.2 requirements:**

MISSING BUT NOT REQUIRED
See also the set of properties for Identifiers:
- ID_Continue
- ID_Start
- XID_Continue
- XID_Start
- Pattern_Syntax
- Pattern_White_Space

#### RL1.2a Compatibility Properties

MISSING
Recommended names of properties for compatibility are listed at http://unicode.org/reports/tr18/#Compatibility_Properties

#### RL1.3 Subtraction and Intersection

- Union is supported in the RPL character class syntax: `\[\[C1\] \[C2\]\]`
- `Intersection(C1, C2)`: "@C1 C2" where C1, C2 match a single codepoint in class C1, C2
- Set difference `C2 - C1`: "!C1 C2" where C1, C2 match a single codepoint in class C1, C2

#### RL1.4 Simple Word Boundaries

Need to compare the current definition of ~ (token boundary) with the one in http://unicode.org/reports/tr18/#RL1.4

#### RL1.5 Simple Loose Matches

Since case-insensitive matching is not an explicit feature of RPL, this requirement does not have to be met.

#### RL1.6 Line Boundaries

See definitions in the `utf8` package.

#### RL1.7 Supplementary Code Points

RPL meets the requirement that Unicode text is interpreted semantically by code
point (provided this is the intent of the user, who then agrees to avoid
arbitrary hex escapes and other non-Unicode features).

For UTF-16 Surrogate matching in RPL, see the `utf8` package.

#### RL2.5 Name Properties

MISSING
MAYBE we will generate a package of patterns of codepoints by name.


