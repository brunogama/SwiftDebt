"""Frozen synthetic source cases for repository rule qualification."""

from __future__ import annotations

from collections.abc import Callable


PATTERNS: dict[str, list[str]] = {
    "data-clumps-functions-positive": [
        "plain scalar parameter types",
        "optional parameter types",
        "nested generic parameter types",
        "function and closure parameter types",
        "existential and composition parameter types",
        "metatype parameter types",
        "matching inout parameter modifiers",
        "matching variadic final parameters",
        "different external labels with equal local names",
        "different default expressions, which are outside the element key",
    ],
    "data-clumps-name-mismatch": [
        "one local identifier is renamed",
        "identifier case differs",
        "singular and plural identifiers differ",
        "equal external labels hide different local identifiers",
        "one local identifier is omitted with an underscore",
        "escaped keyword and unrelated identifier differ",
        "abbreviation and expanded identifier differ",
        "domain synonyms are not treated as equal",
        "two local identifiers are transposed onto different types",
        "a duplicate local identifier collapses the observed set",
    ],
    "data-clumps-type-mismatch": [
        "Int and Int64 are distinct type spellings",
        "optional and nonoptional types differ",
        "Array and Set types differ",
        "tuple element labels differ",
        "generic arguments differ",
        "async and synchronous function types differ",
        "some and any types differ",
        "metatype kinds differ",
        "inout and value parameters differ",
        "variadic and array parameters differ",
    ],
    "data-clumps-properties-positive": [
        "plain let properties in two structs",
        "stored properties shared by a class and actor",
        "stored var properties with different initializers",
        "stored properties with different observers",
        "different access-control modifiers",
        "nested generic property types",
        "optional and result property types",
        "function and metatype property types",
        "lazy stored properties with explicit types",
        "escaped identifiers normalized to the same local names",
    ],
    "data-clumps-only-two-shared": [
        "third property has a different local name",
        "third property has a different explicit type",
        "third property is static in one owner",
        "third property has an inferred type in one owner",
        "third property is computed in one owner",
        "third property is a class property in one owner",
        "third property uses a wildcard pattern in one owner",
        "third property is nested in a callable-local type",
        "third property is absent from one owner",
        "each owner has a distinct extra property beyond two shared fields",
    ],
    "data-clumps-computed-properties": [
        "shorthand computed getters are excluded",
        "explicit get accessors are excluded",
        "get-set accessors are excluded",
        "read accessors are excluded",
        "modify accessors are excluded",
        "enum properties are outside the supported nominal kinds",
        "properties in callable-local types are excluded",
        "static stored properties are excluded",
        "class computed properties are excluded",
        "stored properties without explicit types are excluded",
    ],
    "data-clumps-init-subscript-positive": [
        "initializer and subscript parameters",
        "two initializer overloads",
        "two subscript overloads",
        "different external labels with equal local names",
        "different default expressions",
        "matching inout modifiers",
        "matching variadic final parameters",
        "nested generic types",
        "escaped local identifiers",
        "initializer and method parameter lists",
    ],
    "data-clumps-unnamed-parameters": [
        "all subscript parameters are unnamed",
        "two of three subscript parameters are unnamed",
        "all second-initializer parameters are unnamed",
        "all second-method parameters are unnamed",
        "one wildcard plus one renamed local leaves one match",
        "external labels do not rescue wildcard local names",
        "wildcards with default expressions remain excluded",
        "wildcards with optional types remain excluded",
        "wildcards with generic types remain excluded",
        "wildcards with a variadic final parameter remain excluded",
    ],
    "data-clumps-token-boundary": [
        "some P and someP remain distinct",
        "any P and anyP remain distinct",
        "inout P and inoutP remain distinct",
        "optional and similarly named nominal types remain distinct",
        "member types and flattened identifiers remain distinct",
        "generic types and flattened identifiers remain distinct",
        "tuple types and nominal lookalikes remain distinct",
        "function types and nominal lookalikes remain distinct",
        "protocol compositions and nominal lookalikes remain distinct",
        "metatypes and nominal lookalikes remain distinct",
    ],
    "repeated-switches-methods-positive": [
        "identifier discriminator with enum cases",
        "self member-access discriminator",
        "nested member-access discriminator",
        "binding case labels",
        "matching where clauses",
        "matching type-cast patterns",
        "matching range patterns",
        "matching default branches",
        "matching combined case items",
        "different case bodies with one dispatch shape",
    ],
    "repeated-switches-discriminator-mismatch": [
        "different local identifiers",
        "identifier case differs",
        "local identifier and nested member access differ",
        "different base identifiers for member access",
        "different member names on one base",
        "member-access chain lengths differ",
        "different nested members",
        "domain synonyms remain distinct",
        "different members on self differ",
        "two independently named state values remain distinct",
    ],
    "repeated-switches-case-order-mismatch": [
        "reversed disjoint enum cases are a candidate equivalent dispatch",
        "default position changes without changing the listed specific case",
        "rotated disjoint enum cases are a candidate equivalent dispatch",
        "binding and literal cases use the same candidate partition in a new order",
        "where-constrained and fallback cases use the same candidate partition in a new order",
        "type-cast cases use the same candidate partition in a new order",
        "disjoint range cases use the same candidate partition in a new order",
        "combined case items reverse inside one candidate equivalent branch",
        "nil and value cases use the same candidate partition in a new order",
        "wildcard and literal ordering needs semantic reachability analysis",
    ],
    "repeated-switches-case-set-mismatch": [
        "different enum cases are singled out",
        "nil and one specific wrapped value are singled out",
        "different integer literals are singled out",
        "disjoint integer ranges are singled out",
        "different tuple positions are constrained",
        "one specific success and a failure are singled out",
        "different associated-value cases are singled out",
        "different string literals are singled out",
        "different runtime types are singled out",
        "disjoint enum case groups are singled out",
    ],
    "repeated-switches-nested-positive": [
        "one-level nested struct scope",
        "two-level nested struct scope",
        "nested class scope",
        "nested actor scope",
        "member-access discriminator in a nested scope",
        "three-member access chain in a nested scope",
        "binding patterns in a nested scope",
        "where clauses in a nested scope",
        "default branch in a nested scope",
        "different bodies in a nested scope",
    ],
    "repeated-switches-scope-mismatch": [
        "sibling nested structs",
        "different outer structs",
        "nested class and nested actor",
        "top-level and nested scopes",
        "nested scopes at different depths",
        "same inner name under different outers",
        "struct and class scopes",
        "actor and struct scopes",
        "enum and struct scopes",
        "two unrelated nominal owners",
    ],
    "repeated-switches-associated-pattern-mismatch": [
        "different integer payload values are singled out",
        "different string payload values are singled out",
        "different tuple payload positions are constrained",
        "different associated-value cases are singled out",
        "a constrained success and a failure case are singled out",
        "different optional payload positions are constrained",
        "different nested error cases are singled out",
        "different labeled payload positions are constrained",
        "a literal node value and empty children are singled out",
        "different associated-value ranges are singled out",
    ],
    "repeated-switches-token-boundary": [
        "case let value and case letvalue remain distinct",
        "some binding tokens and a flattened name remain distinct",
        "type-cast tokens and a flattened name remain distinct",
        "is pattern tokens and a flattened name remain distinct",
        "member pattern tokens and a flattened name remain distinct",
        "optional pattern tokens and a flattened name remain distinct",
        "range operator tokens and a nominal name remain distinct",
        "tuple pattern tokens and a nominal name remain distinct",
        "where clause tokens and an identifier suffix remain distinct",
        "combined-case punctuation and one nominal name remain distinct",
    ],
    "repeated-switches-extensions-positive": [
        "two extensions in separate files",
        "two extensions of one member type in separate files",
        "self member access across extensions",
        "nested member access across extensions",
        "binding patterns across extensions",
        "where clauses across extensions",
        "type-cast patterns across extensions",
        "default branches across extensions",
        "combined case items across extensions",
        "different bodies across extensions",
    ],
    "repeated-switches-compound-discriminator": [
        "call expressions are not simple discriminators",
        "subscript expressions are not simple discriminators",
        "tuple expressions are not simple discriminators",
        "binary expressions are not simple discriminators",
        "ternary expressions are not simple discriminators",
        "forced-value expressions are not simple discriminators",
        "optional-chain expressions are not simple discriminators",
        "cast expressions are not simple discriminators",
        "await expressions are not simple discriminators",
        "try expressions are not simple discriminators",
    ],
    "repeated-switches-where-clause": [
        "only one switch has a where clause",
        "where constants differ",
        "where comparison operators differ",
        "where-bound values feed different expressions",
        "where conjunction terms differ",
        "where membership ranges differ",
        "where boolean literals differ",
        "where member names differ",
        "where function names differ",
        "where clauses appear on different case items",
    ],
    "repeated-switches-branch-partition-mismatch": [
        "three explicit enum branches contract to one explicit branch",
        "four explicit enum branches contract to two explicit branches",
        "two integer literals contract to one literal",
        "two integer ranges contract to one range",
        "two string literals contract to one literal",
        "two optional value predicates contract to one predicate",
        "two tuple patterns contract to one pattern",
        "two runtime type patterns contract to one type",
        "success and failure predicates contract to success only",
        "two combined enum groups contract to one combined group",
    ],
}


def render_case(template: str, ordinal: int) -> dict[str, str]:
    """Return relative source paths and bytes for one immutable case."""
    if template not in PATTERNS or not 0 <= ordinal < len(PATTERNS[template]):
        raise ValueError(f"Unknown case variant: {template}[{ordinal}]")
    renderer = _RENDERERS[template]
    rendered = renderer(ordinal)
    base, salt = _CASE_SALTS[template]
    old_stem = f"{base}{ordinal:02d}"
    new_stem = f"{salt}{ordinal:02d}"
    return {path: source.replace(old_stem, new_stem) for path, source in rendered.items()}


def case_pattern(template: str, ordinal: int) -> str:
    return PATTERNS[template][ordinal]


def normalized_rendered_case(template: str, ordinal: int) -> str:
    """Return rendered source with its per-case identifier salt removed."""
    _, salt = _CASE_SALTS[template]
    marker = f"{salt}{ordinal:02d}"
    rendered = render_case(template, ordinal)
    return "\n".join(
        source.replace(marker, "<case>") for _, source in sorted(rendered.items())
    )


def _data_functions(ordinal: int, mismatch: str | None = None) -> dict[str, str]:
    stem = f"d{ordinal:02d}"
    triples = [
        ("String", "Int", "Bool"),
        ("String?", "Int?", "Bool?"),
        ("Result<String, Error>", "[String: [Int]]", "Set<String>"),
        ("@Sendable (Int) -> String", "(String) async throws -> Bool", "(() -> Void)?"),
        ("any P", "any Q & Sendable", "some R"),
        ("String.Type", "(any P).Type", "Int.Type"),
        ("inout Int", "inout String", "inout Bool"),
        ("String", "Int", "Bool..."),
        ("String", "Int", "Bool"),
        ("String", "Int", "Bool"),
    ]
    types_a = list(triples[ordinal])
    types_b = list(types_a)
    names_a = [f"account{stem}", f"region{stem}", f"enabled{stem}"]
    names_b = list(names_a)
    if mismatch == "name":
        variants = [
            f"customer{stem}", names_a[0].upper(), f"accounts{stem}", f"local{stem}", "_",
            f"classValue{stem}", f"identifier{stem}", f"client{stem}", f"region{stem}", names_a[0],
        ]
        names_b[0] = variants[ordinal]
        if ordinal == 8:
            names_b[0], names_b[1] = names_a[1], names_a[0]
        if ordinal == 9:
            names_b[2] = names_a[1]
    if mismatch == "type":
        replacements = [
            "Int64", "String", "Set<String>", "(value: String, Int)", "Result<Int, Error>",
            "(String) throws -> Bool", "any R", "String.Protocol", "Int", "[Bool]",
        ]
        base = [
            "Int", "String?", "[String]", "(name: String, Int)", "Result<String, Error>",
            "(String) async throws -> Bool", "some R", "String.Type", "inout Int", "Bool...",
        ]
        types_a[0] = base[ordinal]
        types_b[0] = replacements[ordinal]
    def params(names: list[str], types: list[str], second: bool) -> str:
        values = []
        for index, (name, type_name) in enumerate(zip(names, types, strict=True)):
            if ordinal == 8 and mismatch is None:
                external = ["source", "area", "flag"] if not second else ["input", "zone", "state"]
                values.append(f"{external[index]} {name}: {type_name}")
            else:
                values.append(f"{name}: {type_name}")
        if ordinal == 9 and mismatch is None:
            defaults = ["\"a\"", "1", "true"] if not second else ["\"b\"", "2", "false"]
            values = [f"{value} = {default}" for value, default in zip(values, defaults, strict=True)]
        return ", ".join(values)
    source = (
        f"func first{stem}({params(names_a, types_a, False)}) {{}}\n"
        f"func second{stem}({params(names_b, types_b, True)}) {{}}\n"
    )
    return {"Case.swift": source}


def _data_properties(ordinal: int, mode: str) -> dict[str, str]:
    stem = f"p{ordinal:02d}"
    names = [f"account{stem}", f"region{stem}", f"enabled{stem}"]
    types = ["String", "Int", "Bool"]
    if mode == "positive":
        type_sets = [
            types, types, types, types, types, ["[String: [Int]]", "Set<String>", "Result<Int, Error>"],
            ["String?", "Int?", "Result<Bool, Error>"], ["(Int) -> String", "String.Type", "Int.Type"],
            types, types,
        ]
        selected = type_sets[ordinal]
        escaped = [f"`class{stem}`", f"`switch{stem}`", f"`repeat{stem}`"] if ordinal == 9 else names
        modifiers = "private " if ordinal == 4 else ("lazy " if ordinal == 8 else "")
        left_lines = []
        right_lines = []
        for index, (name, type_name) in enumerate(zip(escaped, selected, strict=True)):
            if ordinal == 2:
                left_lines.append(f"var {name}: {type_name} = {['\"a\"', '1', 'true'][index]}")
                right_lines.append(f"var {name}: {type_name} = {['\"b\"', '2', 'false'][index]}")
            elif ordinal == 3:
                left_lines.append(f"var {name}: {type_name} {{ willSet {{ }} }}")
                right_lines.append(f"var {name}: {type_name} {{ didSet {{ }} }}")
            elif ordinal == 8:
                left_lines.append(f"{modifiers}var {name}: {type_name} = {['\"a\"', '1', 'true'][index]}")
                right_lines.append(f"{modifiers}var {name}: {type_name} = {['\"b\"', '2', 'false'][index]}")
            else:
                left_lines.append(f"{modifiers}let {name}: {type_name}")
                right_lines.append(f"{modifiers}let {name}: {type_name}")
        left_kind, right_kind = ("class", "actor") if ordinal == 1 else ("struct", "struct")
        return {"Case.swift": _two_nominals(stem, left_kind, right_kind, left_lines, right_lines)}

    left = [f"let {names[i]}: {types[i]}" for i in range(3)]
    right = [f"let {names[i]}: {types[i]}" for i in range(2)]
    if mode == "two":
        extras = [
            f"let customer{stem}: Bool", f"let {names[2]}: Int", f"static let {names[2]}: Bool = false",
            f"let {names[2]} = false", f"var {names[2]}: Bool {{ false }}", f"class var {names[2]}: Bool {{ false }}",
            "let _: Bool", "", "", f"let other{stem}: Bool",
        ]
        if ordinal == 8:
            left.append(f"let {names[2]}: Bool")
        right.append(extras[ordinal])
        if ordinal == 7:
            right.append(f"func nested() {{ struct Local {{ let {names[2]}: Bool }} }}")
        if ordinal == 9:
            left.append(f"let own{stem}: Bool")
        return {"Case.swift": _two_nominals(stem, "struct", "struct", left, right)}

    computed_sets = [
        [f"var {n}: {t} {{ {_zero(t)} }}" for n, t in zip(names, types, strict=True)],
        [f"var {n}: {t} {{ get {{ {_zero(t)} }} }}" for n, t in zip(names, types, strict=True)],
        [f"var {n}: {t} {{ get {{ {_zero(t)} }} set {{ }} }}" for n, t in zip(names, types, strict=True)],
        [f"var {n}: {t} {{ _read {{ yield {_zero(t)} }} }}" for n, t in zip(names, types, strict=True)],
        [f"var {n}: {t} {{ _modify {{ fatalError() }} }}" for n, t in zip(names, types, strict=True)],
    ]
    if ordinal < 5:
        right = computed_sets[ordinal]
        return {"Case.swift": _two_nominals(stem, "struct", "struct", left, right)}
    if ordinal == 5:
        right_body = "\n".join(f"  var {n}: {t} {{ {_zero(t)} }}" for n, t in zip(names, types, strict=True))
        return {"Case.swift": f"struct Stored{stem} {{\n  " + "\n  ".join(left) + f"\n}}\nenum Other{stem} {{\n{right_body}\n}}\n"}
    if ordinal == 6:
        local = "\n".join(f"    let {n}: {t}" for n, t in zip(names, types, strict=True))
        return {"Case.swift": f"struct Stored{stem} {{\n  " + "\n  ".join(left) + f"\n}}\nfunc make{stem}() {{\n  struct Local {{\n{local}\n  }}\n}}\n"}
    prefixes = ["static let", "class var", "let"]
    prefix = prefixes[ordinal - 7]
    if ordinal == 7:
        right = [f"{prefix} {n}: {t} = {_zero(t)}" for n, t in zip(names, types, strict=True)]
    elif ordinal == 8:
        right = [f"{prefix} {n}: {t} {{ {_zero(t)} }}" for n, t in zip(names, types, strict=True)]
    else:
        right = [f"{prefix} {n} = {_zero(t)}" for n, t in zip(names, types, strict=True)]
    return {"Case.swift": _two_nominals(stem, "struct", "class", left, right)}


def _data_callable(ordinal: int, mode: str) -> dict[str, str]:
    stem = f"c{ordinal:02d}"
    names = [f"account{stem}", f"region{stem}", f"enabled{stem}"]
    types = ["String", "Int", "Bool"]
    if ordinal == 7:
        types = ["Result<String, Error>", "[String: [Int]]", "Set<String>"]
    if ordinal == 8:
        names = [f"`class{stem}`", f"`switch{stem}`", f"`repeat{stem}`"]
    params = ", ".join(f"{name}: {type_name}" for name, type_name in zip(names, types, strict=True))
    if mode == "positive":
        if ordinal == 3:
            first = ", ".join(f"left {n}: {t}" for n, t in zip(names, types, strict=True))
            second = ", ".join(f"right {n}: {t}" for n, t in zip(names, types, strict=True))
        elif ordinal == 4:
            first = params.replace(": String", ": String = \"a\"").replace(": Int", ": Int = 1").replace(": Bool", ": Bool = true")
            second = params.replace(": String", ": String = \"b\"").replace(": Int", ": Int = 2").replace(": Bool", ": Bool = false")
        elif ordinal == 5:
            first = second = ", ".join(f"{n}: inout {t}" for n, t in zip(names, types, strict=True))
        elif ordinal == 6:
            first = second = f"{names[0]}: String, {names[1]}: Int, {names[2]}: Bool..."
        else:
            first = second = params
        if ordinal == 1:
            declarations = f"init(one {first}) {{}}\n  init(two {second}) {{}}"
        elif ordinal == 2:
            declarations = f"subscript(one {first}) -> Int {{ 0 }}\n  subscript(two {second}) -> Int {{ 0 }}"
        elif ordinal == 9:
            declarations = f"init({first}) {{}}\n  func update({second}) {{}}"
        else:
            declarations = f"init({first}) {{}}\n  subscript({second}) -> Int {{ 0 }}"
        return {"Case.swift": f"struct Callable{stem} {{\n  {declarations}\n}}\n"}

    wildcard_types = list(types)
    if ordinal == 7:
        wildcard_types = ["String?", "Int?", "Bool?"]
    if ordinal == 8:
        wildcard_types = ["Result<String, Error>", "[String]", "Set<Int>"]
    wildcard = [f"_: {type_name}" for type_name in wildcard_types]
    if ordinal == 1:
        wildcard[2] = f"other{stem}: {wildcard_types[2]}"
    if ordinal == 4:
        wildcard[0] = "_: String"
        wildcard[1] = f"otherRegion{stem}: Int"
        wildcard[2] = f"enabled{stem}: Bool"
    if ordinal == 5:
        wildcard = [f"external _: {type_name}" for type_name in wildcard_types]
    if ordinal == 6:
        wildcard = [f"_: {type_name} = {_zero(type_name)}" for type_name in wildcard_types]
    if ordinal == 9:
        wildcard[-1] += "..."
    second = ", ".join(wildcard)
    second_decl = f"subscript({second}) -> Int {{ 0 }}" if ordinal not in (2, 3) else (
        f"init({second}) {{}}" if ordinal == 2 else f"func update({second}) {{}}"
    )
    return {"Case.swift": f"struct Callable{stem} {{\n  init({params}) {{}}\n  {second_decl}\n}}\n"}


def _data_token_boundary(ordinal: int) -> dict[str, str]:
    stem = f"t{ordinal:02d}"
    pairs = [
        ("some P", "someP"), ("any P", "anyP"), ("inout P", "inoutP"),
        ("P?", "POptional"), ("Outer.Inner", "OuterInner"), ("Box<P>", "BoxP"),
        ("(P, Q)", "TuplePQ"), ("(P) -> Q", "FunctionPQ"), ("P & Q", "PAndQ"),
        ("P.Type", "PType"),
    ]
    left_type, right_type = pairs[ordinal]
    names = [f"first{stem}", f"second{stem}", f"third{stem}"]
    left = ", ".join(f"{name}: {left_type}" for name in names)
    right = ", ".join(f"{name}: {right_type}" for name in names)
    return {"Case.swift": f"func left{stem}({left}) {{}}\nfunc right{stem}({right}) {{}}\n"}


def _switch_case(ordinal: int, mode: str) -> dict[str, str]:
    stem = f"s{ordinal:02d}"
    subjects = ["mode", "self.mode", "context.mode", "value", "value", "value", "value", "value", "value", "mode"]
    labels = [
        ["case .idle:", "case .busy:"],
        ["case .idle:", "case .busy:"],
        ["case .idle:", "case .busy:"],
        ["case .some(let value):", "case .none:"],
        ["case let value where value > 0:", "default:"],
        ["case is String:", "case is Int:"],
        ["case 0..<10:", "default:"],
        ["case .idle:", "default:"],
        ["case .idle, .waiting:", "case .busy:"],
        ["case .idle:", "case .busy:"],
    ]
    first_subject = subjects[ordinal]
    second_subject = first_subject
    first_labels = list(labels[ordinal])
    second_labels = list(first_labels)
    if mode == "discriminator":
        subject_pairs = [
            ("mode", "state"), ("mode", "Mode"), ("mode", "context.mode"), ("left.mode", "right.mode"),
            ("context.mode", "context.state"), ("context.mode", "context.current.mode"),
            ("context.inner.mode", "context.outer.mode"), ("status", "phase"),
            ("self.mode", "self.state"), ("primaryState", "secondaryState"),
        ]
        first_subject, second_subject = subject_pairs[ordinal]
        first_labels = second_labels = ["case .idle:", "case .busy:"]
    elif mode == "order":
        order_pairs = [
            (["case .idle:", "case .busy:"], ["case .busy:", "case .idle:"]),
            (["case .idle:", "default:"], ["default:", "case .idle:"]),
            (["case .one:", "case .two:", "case .three:"], ["case .two:", "case .three:", "case .one:"]),
            (["case .some(let value):", "case 0:"], ["case 0:", "case .some(let value):"]),
            (["case let value where value > 0:", "default:"], ["default:", "case let value where value > 0:"]),
            (["case is String:", "case is Int:"], ["case is Int:", "case is String:"]),
            (["case 0..<10:", "case 10..<20:"], ["case 10..<20:", "case 0..<10:"]),
            (["case .idle, .waiting:", "case .busy:"], ["case .waiting, .idle:", "case .busy:"]),
            (["case nil:", "case .some:"], ["case .some:", "case nil:"]),
            (["case _:", "case 1:"], ["case 1:", "case _:"]),
        ]
        first_labels, second_labels = order_pairs[ordinal]
        first_subject = second_subject = "value"
    body_a = _switch_statement(first_subject, first_labels, "first")
    body_b = _switch_statement(second_subject, second_labels, "second" if ordinal == 9 else "first")
    return {"Case.swift": f"struct SwitchOwner{stem} {{\n  func first() {{\n{body_a}  }}\n  func second() {{\n{body_b}  }}\n}}\n"}


def _switch_nested(ordinal: int, mode: str) -> dict[str, str]:
    stem = f"n{ordinal:02d}"
    if mode == "positive":
        owner_kinds = ["struct", "struct", "class", "actor", "struct", "struct", "struct", "struct", "struct", "struct"]
        subject = ["mode", "mode", "mode", "mode", "self.mode", "context.current.mode", "value", "value", "mode", "mode"][ordinal]
        labels = ["case .idle:", "case .busy:"]
        if ordinal == 6: labels = ["case .some(let item):", "case .none:"]
        if ordinal == 7: labels = ["case let item where item > 0:", "default:"]
        if ordinal == 8: labels = ["case .idle:", "default:"]
        nested = f"{owner_kinds[ordinal]} Inner{stem} {{\n  func first() {{\n{_switch_statement(subject, labels, 'a')}  }}\n  func second() {{\n{_switch_statement(subject, labels, 'b' if ordinal == 9 else 'a')}  }}\n}}"
        if ordinal == 1:
            nested = f"struct Middle{stem} {{\n{_indent(nested, 2)}\n}}"
        return {"Case.swift": f"struct Outer{stem} {{\n{_indent(nested, 2)}\n}}\n"}
    if mode == "scope":
        switch = _switch_statement("mode", ["case .idle:", "case .busy:"], "same")
        member = f"func run() {{\n{switch}}}"
        if ordinal == 0:
            source = f"struct Outer{stem} {{\n  struct Left {{\n{_indent(member, 4)}\n  }}\n  struct Right {{\n{_indent(member, 4)}\n  }}\n}}\n"
        elif ordinal == 1:
            source = f"struct LeftOuter{stem} {{\n  struct Inner {{\n{_indent(member, 4)}\n  }}\n}}\nstruct RightOuter{stem} {{\n  struct Inner {{\n{_indent(member, 4)}\n  }}\n}}\n"
        elif ordinal == 2:
            source = f"struct Outer{stem} {{\n  class Left {{\n{_indent(member, 4)}\n  }}\n  actor Right {{\n{_indent(member, 4)}\n  }}\n}}\n"
        elif ordinal == 3:
            source = f"func top{stem}() {{\n{switch}}}\nstruct Nested{stem} {{\n{_indent(member, 2)}\n}}\n"
        elif ordinal == 4:
            source = f"struct Outer{stem} {{\n  struct Inner {{\n{_indent(member, 4)}\n  }}\n  struct Middle {{\n    struct Inner {{\n{_indent(member, 6)}\n    }}\n  }}\n}}\n"
        elif ordinal == 5:
            source = f"class LeftOuter{stem} {{\n  struct Inner {{\n{_indent(member, 4)}\n  }}\n}}\nactor RightOuter{stem} {{\n  struct Inner {{\n{_indent(member, 4)}\n  }}\n}}\n"
        elif ordinal == 6:
            source = f"struct Left{stem} {{\n{_indent(member, 2)}\n}}\nclass Right{stem} {{\n{_indent(member, 2)}\n}}\n"
        elif ordinal == 7:
            source = f"actor Left{stem} {{\n{_indent(member, 2)}\n}}\nstruct Right{stem} {{\n{_indent(member, 2)}\n}}\n"
        elif ordinal == 8:
            source = f"enum Left{stem} {{\n{_indent(member, 2)}\n}}\nstruct Right{stem} {{\n{_indent(member, 2)}\n}}\n"
        else:
            source = f"struct Alpha{stem}<Value> {{\n{_indent(member, 2)}\n}}\nstruct Omega{stem}<Value> {{\n{_indent(member, 2)}\n}}\n"
        return {"Case.swift": source}
    label_pairs = [
        (["case let value:", "default:"], ["case letvalue:", "default:"]),
        (["case .some(let value):", "default:"], ["case .some(letvalue):", "default:"]),
        (["case _ as P:", "default:"], ["case _asP:", "default:"]),
        (["case is P:", "default:"], ["case isP:", "default:"]),
        (["case .outer(.inner):", "default:"], ["case .outerInner:", "default:"]),
        (["case value?:", "default:"], ["case valueOptional:", "default:"]),
        (["case 0..<10:", "default:"], ["case range0to10:", "default:"]),
        (["case (let a, let b):", "default:"], ["case tupleLetALetB:", "default:"]),
        (["case let value where value > 0:", "default:"], ["case let valueWhereValueGreater0:", "default:"]),
        (["case .a, .b:", "default:"], ["case .aCommaB:", "default:"]),
    ]
    first, second = label_pairs[ordinal]
    return {"Case.swift": f"struct Boundary{stem} {{\n  func first() {{\n{_switch_statement('value', first, 'a')}  }}\n  func second() {{\n{_switch_statement('value', second, 'b')}  }}\n}}\n"}


def _switch_extension(ordinal: int, mode: str) -> dict[str, str]:
    stem = f"e{ordinal:02d}"
    owner = f"Router{stem}"
    labels = ["case .idle:", "case .busy:"]
    subject = "mode"
    if mode == "positive":
        if ordinal == 1:
            owner = f"Outer{stem}.Router"
        subjects = ["mode", "mode", "self.mode", "context.mode", "value", "value", "value", "mode", "mode", "mode"]
        label_variants = [
            labels, labels, labels, labels, ["case .some(let item):", "case .none:"],
            ["case let item where item > 0:", "default:"], ["case is String:", "case is Int:"],
            ["case .idle:", "default:"], ["case .idle, .waiting:", "case .busy:"], labels,
        ]
        subject = subjects[ordinal]
        labels = label_variants[ordinal]
        first = f"extension {owner} {{\n  func first() {{\n{_switch_statement(subject, labels, 'a')}  }}\n}}\n"
        second = f"extension {owner} {{\n  func second() {{\n{_switch_statement(subject, labels, 'b' if ordinal == 9 else 'a')}  }}\n}}\n"
        return {"First.swift": first, "Second.swift": second}
    if mode == "compound":
        subjects = [
            "currentMode()", "modes[index]", "(mode, state)", "mode == state", "flag ? mode : state",
            "mode!", "context?.mode", "mode as Any", "await currentMode()", "try currentMode()",
        ]
        subject = subjects[ordinal]
        source = f"extension {owner} {{\n  func first() {{\n{_switch_statement(subject, labels, 'a')}  }}\n  func second() {{\n{_switch_statement(subject, labels, 'b')}  }}\n}}\n"
        return {"Case.swift": source}
    where_pairs = [
        ("case let value where value > 0:", "case let value:"),
        ("case let value where value > 0:", "case let value where value > 1:"),
        ("case let value where value > 0:", "case let value where value >= 0:"),
        ("case let left where left > 0:", "case let right where right.isMultiple(of: 2):"),
        ("case let value where value > 0 && flag:", "case let value where value > 0 && ready:"),
        ("case let value where 0..<10 ~= value:", "case let value where 0..<20 ~= value:"),
        ("case let value where true:", "case let value where false:"),
        ("case let value where value.ready:", "case let value where value.active:"),
        ("case let value where accepts(value):", "case let value where permits(value):"),
        ("case let value where value > 0, 0:", "case -1, let value where value > 0:"),
    ]
    first_label, second_label = where_pairs[ordinal]
    first = [first_label, "default:"]
    second = [second_label, "default:"]
    source = f"extension {owner} {{\n  func first() {{\n{_switch_statement('value', first, 'a')}  }}\n  func second() {{\n{_switch_statement('value', second, 'b')}  }}\n}}\n"
    return {"Case.swift": source}


def _switch_case_set_mismatch(ordinal: int) -> dict[str, str]:
    stem = f"q{ordinal:02d}"
    variants = [
        (
            f"enum Phase{stem} {{ case idle, busy, waiting }}",
            f"Phase{stem}",
            ["case .idle:", "default:"],
            ["case .busy:", "default:"],
        ),
        ("", "Int?", ["case .none:", "default:"], ["case .some(0):", "default:"]),
        ("", "Int", ["case 0:", "default:"], ["case 1:", "default:"]),
        ("", "Int", ["case 0..<10:", "default:"], ["case 10..<20:", "default:"]),
        (
            "",
            "(Int, Int)",
            ["case (0, _):", "default:"],
            ["case (_, 0):", "default:"],
        ),
        (
            f"enum Failure{stem}: Error {{ case rejected }}",
            f"Result<Int, Failure{stem}>",
            ["case .success(0):", "default:"],
            ["case .failure(_):", "default:"],
        ),
        (
            f"enum Mixed{stem} {{ case flag(Bool), count(Int), other }}",
            f"Mixed{stem}",
            ["case .flag(true):", "default:"],
            ["case .count(0):", "default:"],
        ),
        ("", "String", ["case \"\":", "default:"], ["case \"ready\":", "default:"]),
        ("", "Any", ["case is String:", "default:"], ["case is Int:", "default:"]),
        (
            f"enum Stage{stem} {{ case idle, waiting, busy, paused, other }}",
            f"Stage{stem}",
            ["case .idle, .waiting:", "default:"],
            ["case .busy, .paused:", "default:"],
        ),
    ]
    prelude, type_name, first_labels, second_labels = variants[ordinal]
    source = (
        (prelude + "\n" if prelude else "")
        + f"struct CaseSet{stem} {{\n"
        + f"  func first(_ value: {type_name}) {{\n"
        + _switch_statement("value", first_labels, "first")
        + "  }\n"
        + f"  func second(_ value: {type_name}) {{\n"
        + _switch_statement("value", second_labels, "second")
        + "  }\n"
        + "}\n"
    )
    return {"Case.swift": source}


def _switch_branch_partition_mismatch(ordinal: int) -> dict[str, str]:
    stem = f"b{ordinal:02d}"
    variants = [
        (
            f"enum Route{stem} {{ case a, b, c, other }}",
            f"Route{stem}",
            ["case .a:", "case .b:", "case .c:", "default:"],
            ["case .a:", "default:"],
        ),
        (
            f"enum Mode{stem} {{ case a, b, c, d, other }}",
            f"Mode{stem}",
            ["case .a:", "case .b:", "case .c:", "case .d:", "default:"],
            ["case .a:", "case .b:", "default:"],
        ),
        ("", "Int", ["case 0:", "case 1:", "default:"], ["case 0:", "default:"]),
        (
            "",
            "Int",
            ["case 0..<10:", "case 10..<20:", "default:"],
            ["case 0..<10:", "default:"],
        ),
        (
            "",
            "String",
            ["case \"open\":", "case \"closed\":", "default:"],
            ["case \"open\":", "default:"],
        ),
        (
            "",
            "Int?",
            ["case .some(let value) where value > 0:", "case .some(_):", "default:"],
            ["case .some(let value) where value > 0:", "default:"],
        ),
        (
            "",
            "(Int, Int)",
            ["case (0, _):", "case (_, 0):", "default:"],
            ["case (0, _):", "default:"],
        ),
        (
            "",
            "Any",
            ["case is String:", "case is Int:", "default:"],
            ["case is String:", "default:"],
        ),
        (
            f"enum Failure{stem}: Error {{ case rejected }}",
            f"Result<Int, Failure{stem}>",
            [
                "case .success(let value) where value > 0:",
                "case .failure(_):",
                "default:",
            ],
            ["case .success(let value) where value > 0:", "default:"],
        ),
        (
            f"enum State{stem} {{ case a, b, c, d, other }}",
            f"State{stem}",
            ["case .a, .b:", "case .c, .d:", "default:"],
            ["case .a, .b:", "default:"],
        ),
    ]
    prelude, type_name, first_labels, second_labels = variants[ordinal]
    source = (
        (prelude + "\n" if prelude else "")
        + f"struct Partition{stem} {{\n"
        + f"  func first(_ value: {type_name}) {{\n"
        + _switch_statement("value", first_labels, "first")
        + "  }\n"
        + f"  func second(_ value: {type_name}) {{\n"
        + _switch_statement("value", second_labels, "second")
        + "  }\n"
        + "}\n"
    )
    return {"Case.swift": source}


def _switch_associated_pattern_mismatch(ordinal: int) -> dict[str, str]:
    stem = f"u{ordinal:02d}"
    variants = [
        (
            f"enum NumberPayload{stem} {{ case number(Int), none }}",
            f"NumberPayload{stem}",
            "case .number(0):",
            "case .number(1):",
        ),
        (
            f"enum TextPayload{stem} {{ case text(String), none }}",
            f"TextPayload{stem}",
            "case .text(\"\"):",
            "case .text(\"ready\"):",
        ),
        (
            f"enum PointPayload{stem} {{ case point(Int, Int), none }}",
            f"PointPayload{stem}",
            "case .point(0, _):",
            "case .point(_, 0):",
        ),
        (
            f"enum MixedPayload{stem} {{ case state(Bool), count(Int), none }}",
            f"MixedPayload{stem}",
            "case .state(true):",
            "case .count(0):",
        ),
        (
            f"enum Outcome{stem} {{ case success(Int), failure, pending }}",
            f"Outcome{stem}",
            "case .success(let value) where value > 0:",
            "case .failure:",
        ),
        (
            f"enum OptionalPair{stem} {{ case pair(Int?, Int?), none }}",
            f"OptionalPair{stem}",
            "case .pair(.some(_), .none):",
            "case .pair(.none, .some(_)):",
        ),
        (
            f"enum Fault{stem} {{ case network, storage }}\n"
            f"enum ResultState{stem} {{ case failed(Fault{stem}), ok, pending }}",
            f"ResultState{stem}",
            "case .failed(.network):",
            "case .failed(.storage):",
        ),
        (
            f"enum LabeledPoint{stem} {{ case point(x: Int, y: Int), none }}",
            f"LabeledPoint{stem}",
            "case .point(0, _):",
            "case .point(_, 0):",
        ),
        (
            f"indirect enum Tree{stem} {{ case node(Int, [Tree{stem}]), leaf }}",
            f"Tree{stem}",
            "case .node(0, _):",
            "case .node(_, let children) where children.isEmpty:",
        ),
        (
            f"enum Span{stem} {{ case value(Int), none }}",
            f"Span{stem}",
            "case .value(let value) where (0..<10).contains(value):",
            "case .value(let value) where (10..<20).contains(value):",
        ),
    ]
    prelude, type_name, first_label, second_label = variants[ordinal]
    source = (
        prelude
        + "\n"
        + f"struct AssociatedPattern{stem} {{\n"
        + f"  func first(_ value: {type_name}) {{\n"
        + _switch_statement("value", [first_label, "default:"], "first")
        + "  }\n"
        + f"  func second(_ value: {type_name}) {{\n"
        + _switch_statement("value", [second_label, "default:"], "second")
        + "  }\n"
        + "}\n"
    )
    return {"Case.swift": source}


def _two_nominals(stem: str, left_kind: str, right_kind: str, left: list[str], right: list[str]) -> str:
    return (
        f"{left_kind} Left{stem} {{\n  " + "\n  ".join(filter(None, left)) + "\n}\n"
        f"{right_kind} Right{stem} {{\n  " + "\n  ".join(filter(None, right)) + "\n}\n"
    )


def _zero(type_name: str) -> str:
    if "String" in type_name: return '""'
    if "Bool" in type_name: return "false"
    if type_name.endswith("?"): return "nil"
    return "0"


def _switch_statement(subject: str, labels: list[str], marker: str) -> str:
    lines = [f"    switch {subject} {{"]
    for index, label in enumerate(labels):
        lines.append(f"    {label}")
        lines.append(f"      _ = \"{marker}-{index}\"")
    lines.append("    }\n")
    return "\n".join(lines)


def _indent(value: str, spaces: int) -> str:
    prefix = " " * spaces
    return "\n".join(prefix + line if line else line for line in value.splitlines())


_RENDERERS: dict[str, Callable[[int], dict[str, str]]] = {
    "data-clumps-functions-positive": lambda i: _data_functions(i),
    "data-clumps-name-mismatch": lambda i: _data_functions(i, "name"),
    "data-clumps-type-mismatch": lambda i: _data_functions(i, "type"),
    "data-clumps-properties-positive": lambda i: _data_properties(i, "positive"),
    "data-clumps-only-two-shared": lambda i: _data_properties(i, "two"),
    "data-clumps-computed-properties": lambda i: _data_properties(i, "computed"),
    "data-clumps-init-subscript-positive": lambda i: _data_callable(i, "positive"),
    "data-clumps-unnamed-parameters": lambda i: _data_callable(i, "unnamed"),
    "data-clumps-token-boundary": _data_token_boundary,
    "repeated-switches-methods-positive": lambda i: _switch_case(i, "positive"),
    "repeated-switches-discriminator-mismatch": lambda i: _switch_case(i, "discriminator"),
    "repeated-switches-case-order-mismatch": lambda i: _switch_case(i, "order"),
    "repeated-switches-case-set-mismatch": _switch_case_set_mismatch,
    "repeated-switches-nested-positive": lambda i: _switch_nested(i, "positive"),
    "repeated-switches-scope-mismatch": lambda i: _switch_nested(i, "scope"),
    "repeated-switches-associated-pattern-mismatch": _switch_associated_pattern_mismatch,
    "repeated-switches-token-boundary": lambda i: _switch_nested(i, "boundary"),
    "repeated-switches-extensions-positive": lambda i: _switch_extension(i, "positive"),
    "repeated-switches-compound-discriminator": lambda i: _switch_extension(i, "compound"),
    "repeated-switches-where-clause": lambda i: _switch_extension(i, "where"),
    "repeated-switches-branch-partition-mismatch": _switch_branch_partition_mismatch,
}

_CASE_SALTS = {
    "data-clumps-functions-positive": ("d", "dfp"),
    "data-clumps-name-mismatch": ("d", "dnm"),
    "data-clumps-type-mismatch": ("d", "dtm"),
    "data-clumps-properties-positive": ("p", "dpp"),
    "data-clumps-only-two-shared": ("p", "dts"),
    "data-clumps-computed-properties": ("p", "dcp"),
    "data-clumps-init-subscript-positive": ("c", "dci"),
    "data-clumps-unnamed-parameters": ("c", "dup"),
    "data-clumps-token-boundary": ("t", "dtb"),
    "repeated-switches-methods-positive": ("s", "rmp"),
    "repeated-switches-discriminator-mismatch": ("s", "rdm"),
    "repeated-switches-case-order-mismatch": ("s", "rom"),
    "repeated-switches-case-set-mismatch": ("q", "rcs"),
    "repeated-switches-nested-positive": ("n", "rnp"),
    "repeated-switches-scope-mismatch": ("n", "rsm"),
    "repeated-switches-associated-pattern-mismatch": ("u", "rap"),
    "repeated-switches-token-boundary": ("n", "rtb"),
    "repeated-switches-extensions-positive": ("e", "rep"),
    "repeated-switches-compound-discriminator": ("e", "rcd"),
    "repeated-switches-where-clause": ("e", "rwc"),
    "repeated-switches-branch-partition-mismatch": ("b", "rbp"),
}
