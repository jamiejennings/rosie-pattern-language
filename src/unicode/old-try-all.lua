names = {
   "ArabicShaping",
-- "BidiBrackets",                 FUTURE?
-- "BidiCharacterTest",            FUTURE?
-- "BidiMirroring",                FUTURE?
-- "BidiTest",                     FUTURE?
-- "Blocks",                       DONE
-- "CJKRadicals",                  FUTURE?
-- "CaseFolding",                  TODO/CASEFOLDING
-- "CompositionExclusions",        UNSUPPORTED
-- "DerivedAge",                   UNSUPPORTED
-- "DerivedCoreProperties",        DONE
-- "DerivedNormalizationProps",    NORMALIZATION
-- "EastAsianWidth",               FUTURE?/works now
-- "EmojiSources",                 UNSUPPORTED
-- "HangulSyllableType",           FUTURE?/works now
-- "Index",                        N/A
-- "IndicPositionalCategory",      FUTURE?/works now
-- "IndicSyllabicCategory",        FUTURE?/works now
-- "Jamo",                         FUTURE?/works now
   "LineBreak",
-- "NameAliases",                  FUTURE?
-- "NamedSequences",               UNSUPPORTED
-- "NamedSequencesProv",           UNSUPPORTED
-- "NamesList",                    FUTURE?
-- "NormalizationCorrections",     FUTURE?/NORMALIZATION
-- "NormalizationTest",            FUTURE?/NORMALIZATION
-- "NushuSources",                 UNSUPPORTED
-- "PropList",                     DONE
-- "PropertyAliases",              TODO/ALIAS
-- "PropertyValueAliases",         TODO/ALIAS
-- "ReadMe",                       N/A
-- "ScriptExtensions",             ** BROKEN due to value names with spaces? multiple values? **
-- "Scripts",                      DONE
-- "SpecialCasing",                UNSUPPORTED
-- "StandardizedVariants",         FUTURE?
-- "TangutSources",                UNSUPPORTED
-- "USourceData",                  UNSUPPORTED
-- "UnicodeData",                  DONE
-- "VerticalOrientation",          UNSUPPORTED
-- "extracted/DerivedBidiClass",          UNSUPPORTED
   "extracted/DerivedBinaryProperties",
-- "extracted/DerivedCombiningClass",     FUTURE?/NORMALIZATION
-- "extracted/DerivedDecompositionType",  FUTURE?/NORMALIZATION
-- "extracted/DerivedEastAsianWidth",     UNSUPPORTED
   "extracted/DerivedGeneralCategory",    --dup?
-- "extracted/DerivedJoiningGroup",       FUTURE?/NORMALIZATION
-- "extracted/DerivedJoiningType",        FUTURE?/NORMALIZATION
   "extracted/DerivedLineBreak",          --dup?
-- "extracted/DerivedName",               FUTURE?
   "extracted/DerivedNumericType",
-- "extracted/DerivedNumericValues",      UNSUPPORTED
   "auxiliary/GraphemeBreakProperty",
-- "auxiliary/GraphemeBreakTest",         N/A
--   "auxiliary/LineBreakTest",           N/A
   "auxiliary/SentenceBreakProperty",
--   "auxiliary/SentenceBreakTest",       N/A
   "auxiliary/WordBreakProperty",
--   "auxiliary/WordBreakTest",           N/A
}

for _,name in ipairs(names) do
   process_ucd_file(name)
   test_property(name)
end
