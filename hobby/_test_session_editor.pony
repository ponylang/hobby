use "collections"
use "pony_test"
use "pony_check"

primitive \nodoc\ _TestSessionEditorList
  fun tests(test: PonyTest) =>
    test(_TestSessionEditorSet)
    test(_TestSessionEditorOverwrite)
    test(_TestSessionEditorRemove)
    test(_TestSessionEditorRemoveMissing)
    test(_TestSessionEditorGetOr)
    test(_TestSessionEditorContains)
    test(_TestSessionEditorRegenerateId)
    test(_TestSessionEditorFinish)
    test(_TestSessionEditorModifiedFlags)
    test(_TestSessionEditorDeletedFlag)
    test(_TestSessionEditorIsNewPassthrough)
    test(_TestSessionResultFields)
    test(Property1UnitTest[(String, String)](_PropEditorSetGetRoundTrip))
    test(Property1UnitTest[(String, String, String, String)](
      _PropEditorSetPreservesOther))
    test(Property1UnitTest[(String, String)](_PropEditorRemoveRemoves))
    test(Property1UnitTest[(String, String)](_PropEditorOriginalUnchanged))

// --- Example-based tests ---

class \nodoc\ iso _TestSessionEditorSet is UnitTest
  fun name(): String => "SessionEditor/set"

  fun apply(h: TestHelper) ? =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    editor.set("user", "alice")
    h.assert_eq[String]("alice", editor("user")?)

class \nodoc\ iso _TestSessionEditorOverwrite is UnitTest
  fun name(): String => "SessionEditor/overwrite"

  fun apply(h: TestHelper) ? =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    editor.set("user", "alice")
    editor.set("user", "bob")
    h.assert_eq[String]("bob", editor("user")?)

class \nodoc\ iso _TestSessionEditorRemove is UnitTest
  fun name(): String => "SessionEditor/remove"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    editor.set("user", "alice")
    editor.remove("user")
    h.assert_false(editor.contains("user"))

class \nodoc\ iso _TestSessionEditorRemoveMissing is UnitTest
  fun name(): String => "SessionEditor/remove-missing"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    editor.remove("absent")
    // Should not error — remove on missing key is a no-op

class \nodoc\ iso _TestSessionEditorGetOr is UnitTest
  fun name(): String => "SessionEditor/get_or"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    editor.set("user", "alice")
    h.assert_eq[String]("alice", editor.get_or("user", "default"))
    h.assert_eq[String]("default", editor.get_or("absent", "default"))

class \nodoc\ iso _TestSessionEditorContains is UnitTest
  fun name(): String => "SessionEditor/contains"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    h.assert_false(editor.contains("user"))
    editor.set("user", "alice")
    h.assert_true(editor.contains("user"))

class \nodoc\ iso _TestSessionEditorRegenerateId is UnitTest
  fun name(): String => "SessionEditor/regenerate_id"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("old-id"))
    let old_id = editor.id()
    try
      editor.regenerate_id()?
    else
      h.fail("regenerate_id failed"); return
    end
    h.assert_true(editor.id() != old_id, "ID should change")
    h.assert_eq[USize](64, editor.id().size(),
      "new ID should be 64 hex chars")
    match editor._get_previous_id()
    | let prev: String val =>
      h.assert_eq[String](old_id, prev)
    else
      h.fail("_previous_id should be the old ID")
    end
    h.assert_true(editor._is_modified())

class \nodoc\ iso _TestSessionEditorFinish is UnitTest
  fun name(): String => "SessionEditor/finish"

  fun apply(h: TestHelper) ? =>
    let original = _TestSessionDataHelper.with_pairs([("a", "1")])
    let editor = SessionEditor._create(original)
    editor.set("b", "2")
    let result = editor._finish()
    h.assert_eq[String]("1", result("a")?)
    h.assert_eq[String]("2", result("b")?)
    h.assert_eq[USize](2, result.size())
    h.assert_false(result.is_new(), "finished session should not be new")

class \nodoc\ iso _TestSessionEditorModifiedFlags is UnitTest
  fun name(): String => "SessionEditor/modified-flags"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    h.assert_false(editor._is_modified(), "fresh editor should not be modified")
    editor.set("key", "val")
    h.assert_true(editor._is_modified(), "should be modified after set")

class \nodoc\ iso _TestSessionEditorDeletedFlag is UnitTest
  fun name(): String => "SessionEditor/deleted-flag"

  fun apply(h: TestHelper) =>
    let editor = SessionEditor._create(SessionData._empty("id1"))
    h.assert_false(editor._is_deleted(), "fresh editor should not be deleted")
    editor.mark_for_deletion()
    h.assert_true(editor._is_deleted(), "should be deleted after mark")

class \nodoc\ iso _TestSessionEditorIsNewPassthrough is UnitTest
  fun name(): String => "SessionEditor/is_new-passthrough"

  fun apply(h: TestHelper) =>
    let new_session = SessionData._empty("id1")
    let editor_new = SessionEditor._create(new_session)
    h.assert_true(editor_new._is_new(), "editor from new session is new")

    let loaded = SessionData._create("id2",
      recover val Map[String, String] end where is_new' = false)
    let editor_loaded = SessionEditor._create(loaded)
    h.assert_false(editor_loaded._is_new(),
      "editor from loaded session is not new")

class \nodoc\ iso _TestSessionResultFields is UnitTest
  fun name(): String => "SessionEditor/_SessionResult-fields"

  fun apply(h: TestHelper) ? =>
    let data = _TestSessionDataHelper.with_pairs([("k", "v")])
    let result = _SessionResult(data, "old-id", true, false, true)
    h.assert_eq[String]("v", result.data("k")?)
    match result.previous_id
    | let prev: String val => h.assert_eq[String]("old-id", prev)
    else h.fail("previous_id should be old-id")
    end
    h.assert_true(result.is_modified)
    h.assert_false(result.is_deleted)
    h.assert_true(result.is_new)

// --- Property-based tests ---

class \nodoc\ iso _PropEditorSetGetRoundTrip is Property1[(String, String)]
  """set(k, v) then apply(k)? returns v."""

  fun name(): String => "SessionEditor/prop-set-get-round-trip"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(0, 100))

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let k, let v) = sample
    let editor = SessionEditor._create(SessionData._empty("id"))
    editor.set(k, v)
    try
      h.assert_eq[String](v, editor(k)?)
    else
      h.fail("apply errored after set")
    end

class \nodoc\ iso _PropEditorSetPreservesOther is
  Property1[(String, String, String, String)]
  """Setting k2 does not affect k1's value."""

  fun name(): String => "SessionEditor/prop-set-preserves-other"

  fun gen(): Generator[(String, String, String, String)] =>
    Generators.zip4[String, String, String, String](
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(0, 100),
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(0, 100))

  fun property(sample: (String, String, String, String),
    h: PropertyHelper)
  =>
    (let k1, let v1, let k2, let v2) = sample
    if k1 == k2 then return end
    let editor = SessionEditor._create(SessionData._empty("id"))
    editor.set(k1, v1)
    editor.set(k2, v2)
    try
      h.assert_eq[String](v1, editor(k1)?)
    else
      h.fail("k1 not found after setting k2")
    end

class \nodoc\ iso _PropEditorRemoveRemoves is Property1[(String, String)]
  """set then remove means contains is false."""

  fun name(): String => "SessionEditor/prop-remove-removes"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(0, 100))

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let k, let v) = sample
    let editor = SessionEditor._create(SessionData._empty("id"))
    editor.set(k, v)
    editor.remove(k)
    h.assert_false(editor.contains(k))

class \nodoc\ iso _PropEditorOriginalUnchanged is
  Property1[(String, String)]
  """Mutating the editor does not change the original SessionData."""

  fun name(): String => "SessionEditor/prop-original-unchanged"

  fun gen(): Generator[(String, String)] =>
    Generators.zip2[String, String](
      Generators.ascii_printable(1, 50),
      Generators.ascii_printable(0, 100))

  fun property(sample: (String, String), h: PropertyHelper) =>
    (let k, let v) = sample
    let original = SessionData._empty("id")
    let editor = SessionEditor._create(original)
    editor.set(k, v)
    h.assert_false(original.contains(k),
      "original should not contain key set on editor")
