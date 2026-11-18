///|
test "reads prefixed LandXML and preserves northing and easting order" {
  let source =
    #|<l:LandXML xmlns:l="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|  <l:Surfaces><l:Surface name="Terrain"><l:Definition surfType="TIN">
    #|    <l:Pnts><l:P id="01">100 200 10</l:P><l:P id="2">100 201 11</l:P><l:P id="3">101 200 12</l:P></l:Pnts>
    #|    <l:Faces><l:F>01 2 3</l:F></l:Faces>
    #|  </l:Definition></l:Surface></l:Surfaces>
    #|</l:LandXML>
  assert_true(@moontin.check(source, max_records=4).passed())
  try @moontin.check(source, max_records=3) catch {
    @moontin.InvalidLandXml(message) =>
      assert_true(message.contains("record limit"))
    error => raise error
  } noraise {
    _ => fail("expected the fourth record to exceed the limit")
  }
  let terrain = @moontin.parse(source)
  let first = terrain.surfaces[0].points[0]
  assert_eq(first.id, "01")
  assert_eq(first.northing, 100.0)
  assert_eq(first.easting, 200.0)
  assert_true(@moontin.validate(terrain).is_empty())
}

///|
test "rejects document type declarations before reading XML events" {
  try
    @moontin.parse("<!DOCTYPE LandXML SYSTEM \"local.dtd\"><LandXML/>")
  catch {
    error => assert_true(error is @moontin.InvalidLandXml(_))
  } noraise {
    _ => fail("expected a LandXML error")
  }
}

///|
test "continues after malformed records and retains original face ordinals" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Metric linearUnit="meter"/></Units>
    #|<Surfaces><Surface name="Terrain"><Definition surfType="TIN">
    #|<Pnts><P id="bad">wrong 200 10</P><P id="1">100 200 10</P><P id="2">100 201 11</P><P id="3">101 200 12</P></Pnts>
    #|<Faces><F>1 2</F><F>1 2 99</F><F>1 2 3</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let report = @moontin.check(source)
  assert_false(report.passed())
  assert_eq(report.record_issues.length(), 2)
  assert_eq(report.record_issues[0].record_kind, "point")
  assert_eq(report.record_issues[1].record_number, 1)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].face_number, Some(2))
  let summary = report.surfaces[0]
  assert_eq(summary.indexed_faces, 1)
  assert_eq(summary.boundary_edges, 3)
  assert_eq(summary.connected_components, 1)
  assert_true(summary.bounds is Some(bounds) && bounds.max_elevation == 12.0)
}

///|
test "counts a connected pair and one isolated face" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Metric linearUnit="meter"/></Units>
    #|<Surfaces><Surface name="Terrain"><Definition surfType="TIN">
    #|<Pnts><P id="1">0 0 0</P><P id="2">0 1 0</P><P id="3">1 0 0</P><P id="4">1 1 0</P>
    #|<P id="5">10 10 0</P><P id="6">10 11 0</P><P id="7">11 10 0</P></Pnts>
    #|<Faces><F>1 2 3</F><F>3 2 4</F><F>5 6 7</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let report = @moontin.check(source)
  assert_true(report.passed())
  assert_eq(report.surfaces[0].connected_components, 2)
  assert_eq(report.surfaces[0].boundary_edges, 7)
  assert_eq(report.surfaces[0].boundary_loops, 2)
}

///|
test "strict mode and truncation use full diagnostic totals" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Surfaces><Surface name="Terrain"><Definition surfType="TIN">
    #|<Pnts><P id="1">0 0 0</P><P id="2">0 1 0</P><P id="3">1 0 0</P></Pnts>
    #|<Faces><F>1 2 3</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let normal = @moontin.check(source, max_diagnostics=0)
  assert_true(normal.passed())
  assert_true(normal.truncated)
  assert_eq(normal.warning_count, 1)
  assert_true(normal.record_issues.is_empty())
  let strict = @moontin.check(source, strict=true, max_diagnostics=0)
  assert_false(strict.passed())
  let failing = @moontin.check(source, area_tolerance=1.0, max_diagnostics=1)
  assert_false(failing.passed())
  assert_true(failing.truncated)
  assert_eq(failing.error_count, 1)
  assert_eq(failing.warning_count, 1)
  assert_eq(failing.record_issues.length() + failing.diagnostics.length(), 1)
}

///|
test "skipped grid surface preserves exact ordinal of later TIN" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Metric linearUnit="meter"/></Units>
    #|<Surfaces><Surface name="Grid"><Definition surfType="GRID"/></Surface>
    #|<Surface name="Terrain"><Definition surfType="TIN">
    #|<Pnts><P id="1">0 0 0</P><P id="2">0 1 0</P><P id="3">1 0 0</P></Pnts>
    #|<Faces><F>1 2 99</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let report = @moontin.check(source)
  assert_eq(report.warning_count, 1)
  assert_eq(report.record_issues[0].surface_number, 1)
  assert_eq(report.error_count, 1)
  assert_eq(report.surfaces[0].surface_number, 2)
  assert_eq(report.diagnostics[0].surface_number, 2)
}

///|
test "reports locations for malformed records, duplicate points and later faces" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Imperial linearUnit="foot"/></Units>
    #|<Surfaces><Surface name="Survey"><Definition surfType="TIN"><Pnts>
    #|  <P id="1">1e3 2e3 3</P>
    #|  <P id="1">1000 2000 4</P>
    #|  <P id="2" pntRef="123"/>
    #|  <P id="3">1001 2000 3</P>
    #|</Pnts><Faces>
    #|  <F>1 3</F>
    #|  <F>1 3 99</F>
    #|</Faces></Definition></Surface></Surfaces></LandXML>
  let report = @moontin.check(source)
  assert_eq(report.linear_unit, Some("foot"))
  assert_eq(report.record_issues[0].code, "invalid_point")
  assert_true(
    report.record_issues[0].message.contains("external point references"),
  )
  assert_eq(report.record_issues[0].location.line, 6)
  assert_eq(report.record_issues[1].location.line, 9)
  assert_eq(report.record_issues[1].location.column, 3)
  assert_eq(report.diagnostics[0].rule.code(), "duplicate_point")
  assert_true(
    report.diagnostics[0].location is Some(position) && position.line == 5,
  )
  assert_eq(report.diagnostics[2].face_number, Some(2))
  assert_true(
    report.diagnostics[2].location is Some(position) && position.line == 10,
  )
}

///|
test "rejects deeply nested XML" {
  let source = StringBuilder()
  for _ in 0..<129 {
    source.write_string("<node>")
  }
  for _ in 0..<129 {
    source.write_string("</node>")
  }
  try @moontin.parse(source.to_string()) catch {
    @moontin.InvalidLandXml(message) =>
      assert_true(message.contains("nesting limit"))
    error => raise error
  } noraise {
    _ => fail("expected the XML nesting limit to be enforced")
  }
}

///|
test "surface counts distinguish invalid visible faces from invisible faces" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Metric linearUnit="meter"/></Units>
    #|<Surfaces><Surface name="Terrain"><Definition surfType="TIN">
    #|<Pnts><P id="1">0 0 0</P><P id="2">0 1 0</P><P id="3">1 0 0</P>
    #|<P id="4">1 1 0</P><P id="4">8 8 8</P></Pnts>
    #|<Faces><F>1 2 3</F><F>1 2 99</F><F i="1">1 3 2</F><F>1 2</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let report = @moontin.check(source)
  let summary = report.surfaces[0]
  assert_eq(summary.decoded_points, 5)
  assert_eq(summary.usable_points, 3)
  assert_eq(summary.decoded_faces, 3)
  assert_eq(summary.indexed_faces, 1)
  assert_eq(summary.skipped_visible_faces, 1)
  assert_eq(summary.invisible_faces, 1)
  assert_eq(report.record_issues.length(), 1)
}

///|
test "two triangles touching at one point produce a branching boundary" {
  let xml =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Metric linearUnit="meter"/></Units>
    #|<Surfaces><Surface name="Terrain"><Definition surfType="TIN">
    #|<Pnts><P id="1">0 0 0</P><P id="2">0 1 0</P><P id="3">1 0 0</P>
    #|<P id="4">0 -1 0</P><P id="5">-1 0 0</P></Pnts>
    #|<Faces><F>1 2 3</F><F>1 4 5</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let report = @moontin.check(xml)
  assert_eq(report.surfaces[0].boundary_loops, 0)
  assert_eq(report.surfaces[0].branched_boundaries, 1)
  assert_eq(report.error_count, 1)
  assert_eq(report.diagnostics[0].rule.code(), "branching_boundary")
  assert_eq(report.diagnostics[0].point_ids, ["1"])
  assert_eq(report.diagnostics[0].related_faces[0].number, 2)
}
