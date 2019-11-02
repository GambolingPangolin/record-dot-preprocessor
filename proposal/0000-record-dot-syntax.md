---
author: Neil Mitchell and Shayne Fletcher
date-accepted: ""
proposal-number: ""
ticket-url: ""
implemented: ""
---

This proposal is [discussed at this pull request](https://github.com/ghc-proposals/ghc-proposals/pull/0>).
**After creating the pull request, edit this file again, update the number in
the link, and delete this bold sentence.**

# Record Dot Syntax

Records in Haskell are [widely recognised](https://www.yesodweb.com/blog/2011/09/limitations-of-haskell) as being under-powered, with duplicate field names being particularly troublesome. We propose a new language extension `RecordDotSyntax` that provides syntactic sugar to make the features introduced in [the `HasField` proposal](https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0158-record-set-field.rst) more accessible, improving the user experience.

## Motivation

In almost every programming language we write `a.b` to mean the `b` field of the `a` record expression. In Haskell that becomes `b a`, and even then, only works if there is only one `b` in scope. Haskell programmers have struggled with this weakness, variously putting each record in a separate module and using qualified imports, or prefixing record fields with the type name. We propose bringing `a.b` to Haskell, which works regardless of how many `b` fields are in scope. Here's a simple example of what is on offer:

```haskell
{-# LANGUAGE RecordDotSyntax #-}

data Company = Company {name :: String, owner :: Person}
data Person = Person {name :: String, age :: Int}

display :: Company -> String
display c = c.name ++ " is run by " ++ c.owner.name

nameAfterOwner :: Company -> Company
nameAfterOwner c = c{name = c.owner.name ++ "'s Company"}
```

We declare two records both having `name` as a field label. The user may then write `c.name` and `c.owner.name` to access those fields. We can also write `c{name = x}` as a record update, which works even though `name` is no longer unique. Under the hood, we make use of `getField` and `setField` from [the `HasField` proposal](https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0158-record-set-field.rst).

An implementation of this proposal has been battle tested and hardened over 18 months in the enterprise environment as part of [Digital Asset](https://digitalasset.com/)'s [DAML](https://daml.com/) smart contract language (a Haskell derivative utilizing GHC in its implementation), and also in a [Haskell preprocessor and a GHC plugin](https://github.com/ndmitchell/record-dot-preprocessor/). When initially considering Haskell as a basis for DAML, the inadequacy of records was considered the most severe problem, and without devising the scheme presented here, we wouldn't be using Haskell. The feature enjoys universal popularity with users.

## Proposed Change Specification

For the specification we focus on the changes to the parsing rules, and the desugaring, with the belief the type checking and renamer changes required are unambiguous consequences of those. To confirm these changes integrate as expected we have written [a prototype implementation](https://gitlab.haskell.org/shayne-fletcher-da/ghc/commits/record-dot-syntax) that parses and desugars the forms directly in the parser. For confirmation, we _do not_ view desugaring in the parser as the correct implementation choice, but it provides a simple mechanism to pin down the changes without going as far as adding additional AST nodes or type checker rules.

### `RecordDotSyntax` language extension

This change adds a new language extension (enabled at source via `{-# LANGUAGE RecordDotSyntax #-}` or on the command line via the flag `-XRecordDotSyntax`).

When `RecordDotSyntax` is in effect, the use of '.' to denote record field access is disambiguated from function composition by the absence of whitespace trailing the '.'.

Suppose the following datatype declarations.

```haskell
data Foo = Foo {foo :: Bar}
data Bar = Bar {bar :: Baz}
data Baz = Baz {baz :: Quux}
data Quux = Quux {quux :: Int}
```

The existence of the builtin `HasField` typeclass means that it is possible to write code for getting and setting record fields like this:

```haskell
getQuux :: Foo -> Int
getQuux a = getField @"quux" (getField @"baz" (getField @"bar" (getField @"foo" a)))

setQuux :: Foo -> Int -> Foo
setQuux a i = setField@"foo" a (setField@"bar" (getField @"foo" a) (setField@"baz" (getField @"bar" (getField @"foo" a)) (setField@"quux" (getField @"baz" (getField @"bar" (getField @"foo" a))) i)))
```

`RecordDotSyntax` enables new concrete syntax so that the following program is equivalent.

```haskell
getQuux a = a.foo.bar.baz.quux
setQuux a i = a{foo.bar.baz.quux = i}
```

In the event the language extension is enabled:

| Expression | Equivalent |
| -- | -- |
| `e.lbl` | `getField @"lbl" e` the `.` cannot have whitespace after |
| `e{lbl = val}` | `setField @"lbl" e val` |
| `(.lbl)` | `(\x -> x.lbl)` the `.` cannot have whitespace after |
| `e{lbl1.lbl2 = val}` | `e{lbl1 = (e.lbl1){lbl2 = val}}` performing a nested update |
| `e{lbl * val}` | `e{lbl = e.lbl * val}` where `*` can be any operator |
| `e{lbl1.lbl2}` | `e{lbl1.lbl2 = lbl2}` when punning is enabled |

The above forms combine to provide these identities:

| Expression | Identity
| -- | -- |
| `e.lbl1.lbl2` | `(e.lbl1).lbl2` |
| `(.lbl1.lbl2)` | `(\x -> x.lbl1.lbl2)` |
| `e.lbl1{lbl2 = val}` | `(e.lbl1){lbl2 = val}` |
| `e{lbl1 = val}.lbl2` | `(e{lbl1 = val}).lbl2` |
| `e{lbl1.lbl2 * val}` | `e{lbl1.lbl2 = e.lbl1.lbl2 * val}` |
| `e{lbl1 = val1, lbl2 = val2}` | `(e{lbl1 = val1}){lbl2 = val2}` |
| `e{lbl1.lbl2, ..}` | `e{lbl2=lbl1.lbl2, ..}` when record wild cards are enabled |

### Lexer

A new lexeme *fieldid* is introduced.
<br/>
<br/>*lexeme* → *qvarid* | *qconid* | *qvarsym* | *qconsym*
| *literal* | *special* | *reservedop* | *reservedid* | *fieldid*
<br/>*fieldid* → *.varid*

This specification results in the following.

```haskell
-- Regular expressions
@fieldid = (\. @varid)
...
<0,option_prags> {
  ...
  @fieldid / {ifExtension RecordDotSyntaxBit} { idtoken fieldid }
}
...

-- Token type
data Token
  = ITas
  | ...
  | ITfieldid FastString
  ...

-- Lexer actions
fieldid :: StringBuffer -> Int -> Token
fieldid buf len = let (_dot, buf') = nextChar buf in ITfieldid $! lexemeToFastString buf' (len - 1)
```

Tokens of case `ITfieldid`  may not be issued if `RecordDotSyntax` is not enabled.

### Parser

#### Field selections

To support '.' field selection the *fexp* production is extended.
<br/>
<br/>*fexp*	→ [ *fexp* ] *aexp* | *fexp* *fieldid*

The specification expresses like this.

```haskell
%token
 ...
 FIELDID { L _ (ITfieldid  _) }
%%

...

fexp    :: { ECP }
        : fexp aexp { ...}
        | fexp FIELDID { ...}  -- <- here
        | ...
```

#### Field updates

To support the new forms of '.' field update, the *aexp* production is extended.
<br/>
<br> *aexp* → *aexp⟨qcon⟩* { *pbind* , … , *pbind* }
<br/>*pbind* -> *qvar*=*exp* | *var* *fieldids*=*exp* | *var* *fieldids* *qop* *exp* | *var* [*fieldids*]
<br/>*fieldids* -> *fieldids* *fieldid*

In this table, the newly added cases are shown next to an example expression they enable:

| Production | Example | Commentary |
| -- |  -- | -- |
|*var* *fieldids*=*exp* | `a{foo.bar=2}` | the *var* is `foo`, `.bar` is a fieldid |
|*var* *fieldids* *qop* *exp* | `a{foo.bar * 12}`   | update `a`'s `foo.bar` field to 12 times its initial value |
|*var* [*fieldids*] | `a{foo.bar}` | means `a{foo.bar = bar}` when punning is enabled |

For example, support for expressions like `a{foo.bar.baz.quux=i}` can be had with one additional case:

```haskell
aexp1   :: { ECP }
        : aexp1 '{' fbinds '}' { ... }
        | aexp1 '{' VARID fieldids '=' texp '}' {...} -- <- here

fieldids :: {[FastString]}
fieldids
        : fieldids FIELDID { getFIELDID $2 : $1 }
        | FIELDID { [getFIELDID $1] }

{
getFIELDID      (dL->L _ (ITfieldid   x)) = x
}
```

An implementation of `RecordDotSyntax` will have to do more than this to incorporate all alternatives.

#### Sections

To support '.' sections (e.g. `(.foo.bar.baz)`), we generalize *aexp*.
<br/>
<br/>*aexp* →	( *infixexp* *qop* ) (left section)
          | ( *qop* *infixexp* )	 (right section)
          | ( *fieldids* )           (projection (right) section)

This specification implies the following additional case to `aexp2`.

```haskell
aexp2   :: { ECP }
        ...
        | '(' texp ')' {...}
        | '(' fieldids ')' {...} -- <- here
```

## Examples

This is a record type with functions describing a study `Class` (*Oh! Pascal, 2nd ed. Cooper & Clancy, 1985*).

```haskell
data Grade = A | B | C | D | E | F
data Quarter = Fall | Winter | Spring
data Status = Passed | Failed | Incomplete | Withdrawn

data Taken =
  Taken { year : Int
        , term : Quarter
        }

data Class =
  Class { hours : Int
        , units : Int
        , grade : Grade
        , result : Status
        , taken : Taken
        }

getResult :: Class -> Status
getResult c = c.result -- get

setResult :: Class -> Status -> Class
setResult c r = c{result = r} -- update

setYearTaken :: Class -> Int -> Class
setYearTaken c y = c{taken.year = y} -- nested update

addYears :: Class -> Int -> Class
addYears c n = c{taken.year + n} -- update via op

squareUnits :: Class -> Class
squareUnits c = c{units & (\x -> x * x)} -- update via function

getResults :: [Class] -> [Status]
getResults = map (.result) -- section

getTerms :: [Class]  -> [Quarter]
getTerms = map (.taken.term) -- nested section
```

A full, rigorous set of examples (as tests) are available in the examples directory of [this repository](https://github.com/ndmitchell/record-dot-preprocessor). Those tests include infix applications, polymorphic data types, interoperation with other extensions and more. They follow the [specifications given earlier](#proposed-change-specification).

## Effect and Interactions

**Polymorphic updates:** When enabled, this extension takes the `a{b=c}` syntax and uses it to mean `setField`. The biggest difference a user is likely to experience is that the resulting type of `a{b=c}` is the same as the type `a` - you _cannot_ change the type of the record by updating its fields. The removal of polymorphism is considered essential to preserve decent type inference, and is the only option supported by [the `HasField` proposal](https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0158-record-set-field.rst).

**Stealing a.b syntax:** The `a.b` syntax is commonly used in conjunction with the `lens` library, e.g. `expr^.field1.field2`. Treating `a.b` without spaces as a record projection would break such code. The alternatives would be to use a library with a different lens composition operator (e.g. `optics`), introduce an alias in `lens` for `.` (perhaps `%`), write such expressions with spaces, or not enable this extension when also using lenses. While unfortunate, we consider that people who are heavy users of lens don't feel the problems of inadequate records as strongly, so the problems are lessened.

**Rebindable syntax:** When `RebindableSyntax` is enabled the `getField`, `setField` and `modifyField` functions are those in scope, rather than those in `GHC.Records`.

**Enabled extensions:** When `RecordDotSyntax` is enabled it should imply the `NoFieldSelectors` extension and allow duplicate record field labels. It would be possible for `RecordDotSyntax` to imply `DuplicateRecordFields`, but we suspect that if people become comfortable with `RecordDotSyntax` then there will be a desire to remove the `DuplicateRecordFields` extension, so we don't want to build on top of it.

## Costs and Drawbacks

The implementation of this proposal adds code to the compiler, but not a huge amount. Our [prototype implementation](https://gitlab.haskell.org/shayne-fletcher-da/ghc/commits/record-dot-syntax) shows the essence of the parsing changes, which is the most complex part.

If this proposal becomes widely used then it is likely that all Haskell users would have to learn that `a.b` is a record field selection. Fortunately, given how popular this syntax is elsewhere, that is unlikely to surprise new users.

This proposal advocates a different style of writing Haskell records, which is distinct from the existing style. As such, it may lead to the bifurcation of Haskell styles, with some people preferring the lens approach, and some people preferring the syntax presented here. That is no doubt unfortunate, but hard to avoid - `a.b` really is ubiquitous in programming languages. We consider that any solution to the records problem _must_ cause some level of divergence, but note that this mechanism (as distinct from some proposals) localises that divergence in the implementation of a module - users of the module will not know whether its internals used this extension or not.

## Alternatives

The primary alternatives to the problem of records are:

* Using the [`lens` library](https://hackage.haskell.org/package/lens). The concept of lenses is very powerful, but that power can be [complex to use](https://twitter.com/fylwind/status/549342595940237312?lang=en). In many ways lenses let you abstract over record fields, but Haskell has neglected the "unabstracted" case of concrete fields.
* The [`DuplicateRecordFields` extension](https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#duplicate-record-fields) is designed to solve similar problems. We evaluated this extension as the basis for DAML, but found it lacking. The rules about what types must be inferred by what point are cumbersome and tricky to work with, requiring a clear understanding of at what stage a type is inferred by the compiler.
* Some style guidelines mandate that each record should be in a separate module. That works, but then requires qualified modules to access fields - e.g. `Person.name (Company.owner c)`. Forcing the structure of the module system to follow the records also makes circular dependencies vastly more likely, leading to complications such as boot files that are ideally avoided.
* Some style guidelines suggest prefixing each record field with the type name, e.g. `personName (companyOwner c)`. While it works, it isn't pleasant, and many libraries then abbreviate the types to lead to code such as `prsnName (coOwner c)`, which can increase confusion.
* There is a [GHC plugin and preprocessor](https://github.com/ndmitchell/record-dot-preprocessor) that both implement much of this proposal. While both have seen light use, their ergonomics are not ideal. The preprocessor struggles to give good location information given the necessary expansion of substrings. The plugin cannot support the full proposal and leads to error messages mentioning `getField`. Suggesting either a preprocessor or plugin to beginners is not an adequate answer. One of the huge benefits to the `a.b` style in other languages is support for completion in IDE's, which is quite hard to give for something not actually in the language.
* Continue to [vent](https://www.reddit.com/r/haskell/comments/vdg55/haskells_record_system_is_a_cruel_joke/) [about](https://bitcheese.net/haskell-sucks) [records](https://medium.com/@snoyjerk/least-favorite-thing-about-haskal-ef8f80f30733) [on](https://www.quora.com/What-are-the-worst-parts-about-using-Haskell) [social](http://www.stephendiehl.com/posts/production.html) [media](https://www.drmaciver.com/2008/02/tell-us-why-your-language-sucks/).

All these approaches are currently used, and represent the "status quo", where Haskell records are considered not fit for purpose.

## Unresolved Questions

Below are some possible variations on this plan, but we advocate the choices made above:

* Should `RecordDotSyntax` imply `NoFieldSelectors`? They are often likely to be used in conjunction, but they aren't inseparable.
* It seems appealing that `a{field += 1}` would be the syntax for incrementing a field. However, `+=` is a valid operator (would that be `a{field +== 1}`?) and for infix operators like `div` would that be <tt>\`div\`=</tt>?
* We do not extend pattern matching, although it would be possible for `P{foo.bar=Just x}` to be defined.

## Implementation Plan

If accepted, the proposal authors would be delighted to provide an implementation. Implementation depends on the implementation of [the `HasField` proposal](https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0158-record-set-field.rst) and [the `NoFieldSelectors` proposal](https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0160-no-toplevel-field-selectors.rst).
