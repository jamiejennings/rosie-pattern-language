## Rules of thumb in deciding what to support

- Generative data is usually NOT supported.  This is our term for data used to generate (and
  sometimes manipulate) renderings.  E.g. Canonical Combining Class, Special Casing Conditions.

- Contributory properties are NOT supported.  These are defined in Unicode TR#44, Section 5.5
  as "incomplete by themselves and are not intended for independent use."

- Properties that do not appear to be useful for matching (to us, at this moment, based on
  necessarily limited knowledge of the matching tasks faced by Rosie users).  E.g. Age, Name,
  Bidi Class.


## Unicode reference

The reference version for these notes is Unicode 10.0.0.


## Sources of Unicode character properties

Properties are extracted from 3 sources in the UCD:

(1) UnicodeData.txt, which has the following fields:

    0) Codepoint in hex
    1) Name
    2) General Category (Enumeration)
    3) Canonical Combining Class
    4) Bidi Class (Enumeration)
    5) Decomposition Type and Mapping
    6,7,8) Numeric Type and Value
    9) Bidi Mirrored (Binary)
    10,11) Obsolete
    12) Simple Uppercase Mapping (Codepoint)
    13) Simple Lowercase Mapping (Codepoint)
    14) Simple Titlecase Mapping (Codepoint)

(2) Property files containing "Catalog" or "Enumeration" property types, which are guaranteed
to be partitions (Unicode TR#44, Section 5.2):

    Block                 (Blocks.txt)
    Script                (Scripts.txt)
    General Category      (extracted/DerivedGeneralCategory.txt)
    LineBreak             (extracted/DerivedLineBreak.txt)
    GraphemeBreakProperty (auxiliary/GraphemeBreakProperty.txt)
    SentenceBreakProperty (auxiliary/SentenceBreakProperty.txt)
    WordBreakProperty     (auxiliary/WordBreakProperty.txt)

(3) Property files containing "Binary" property types

- PropList.txt (x = contributory property, "not intended for independent use"

	```
	ASCII_Hex_Digit
	Bidi_Control
	Dash
	Deprecated
	Diacritic
	Extender
	Hex_Digit
	Hyphen
	IDS_Binary_Operator
	IDS_Trinary_Operator
	Ideographic
	Join_Control
	Logical_Order_Exception
	Noncharacter_Code_Point
	x Other_Alphabetic
	x Other_Default_Ignorable_Code_Point
	x Other_Grapheme_Extend
	x Other_ID_Continue
	x Other_ID_Start
	x Other_Lowercase
	x Other_Math
	x Other_Uppercase
	Pattern_Syntax
	Pattern_White_Space
	Prepended_Concatenation_Mark
	Quotation_Mark
	Radical
	Regional_Indicator
	Sentence_Terminal
	Soft_Dotted
	Terminal_Punctuation
	Unified_Ideograph
	Variation_Selector
	White_Space
	```

- DerivedCoreProperties.txt

	```
	Alphabetic
	Case_Ignorable
	Cased
	Changes_When_Casefolded
	Changes_When_Casemapped
	Changes_When_Lowercased
	Changes_When_Titlecased
	Changes_When_Uppercased
	Default_Ignorable_Code_Point
	Grapheme_Base
	Grapheme_Extend
	Grapheme_Link
	ID_Continue
	ID_Start
	Lowercase
	Math
	Uppercase
	XID_Continue
	XID_Start
	```

Case mappings supported in RPL are derived from two places:

 - UnicodeData.txt

	```
	(12) Simple Uppercase Mapping (Codepoint)
	(13) Simple Lowercase Mapping (Codepoint)
	(14) Simple Titlecase Mapping (Codepoint)
    ```

 - SpecialCasing.txt (conditions are not supported, as they are generative)

	```
    to lower (Codepoint+)
    to title (Codepoint+)
    to upper (Codepoint+)
	```

## On character equivalence and normalization:

Rosie does not understand Unicode character equivalences.  An RPL literal string containing
the single codepoint 00F4, which renders as ô, will match the UTF-8 encoding of 00F4 in the
input, but not the sequence 006F (o) followed by 0302 ( ̂), which is its NFD-decomposed
equivalent. 

How to address such equivalences during matching is an open design question.  A design point
for Rosie is that the input is read-only.  (Any transformations on the input should be done
before Rosie is called.)  Another design point is that the Rosie matching vm is
byte-oriented, with no knowledge of character encodings.  Keeping the vm simple allows for
many optimizations, only some of which are already implemented.  The simplicity of the vm
front-loads some of the matching effort onto the RPL compiler, of course.

For example, Rosie does case-insensitive matching by transforming characters in the pattern
into choices between their lower- and upper-case variants.  In the age of the Unicode
standard, in which case mappings may be complex, case-folding both the input and the pattern
would be costly (whereas it was easy for ASCII).  Also, the use cases for Rosie are not known
to include case-insensitive searching for long literal strings.  Therefore, the current
approach appears to be reasonable.  Time will tell.

But what to do about normalization?  Given the current Rosie implementation, two approaches
are apparent:
(1) Transform the input into a normalized form of choice, and write patterns accordingly; or
(2) Automatically transform string and character literals into an RPL choice between their
    given form and equivalent forms (under the normalization forms deemed relevant).

The second approach is the one Rosie uses today for case-insensitive matching, so it should
be straightforward to adapt it to character equivalence.  Of course, there is more than one
kind of equivalence (under 4 different normalizations), and we currently lack information
about which are important to Rosie users.


##  Regarding reserved, unassigned, and non-characters

Reserved characters and Unassigned characters are valid codepoints which happen
to be unassigned.  They are NOT listed in UnicodeData.txt, and they have the
default General Category "Cn".

Non-Characters are permanently reserved for internal (Unicode) use, i.e. they
will never be assigned.  They are a small fixed list, and are NOT listed in
UnicodeData.txt, but they have the property `Noncharacter_Code_Point` as defined
in Proplist.txt.


