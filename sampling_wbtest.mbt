///|
test "samples an interior point and excludes invisible faces" {
  let source =
    #|<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
    #|<Units><Metric linearUnit="meter"/></Units>
    #|<Surfaces><Surface name="Ground"><Definition surfType="TIN">
    #|<Pnts><P id="1">0 0 10</P><P id="2">0 1 12</P><P id="3">1 0 14</P></Pnts>
    #|<Faces><F>1 2 3</F><F i="1">1 3 2</F></Faces>
    #|</Definition></Surface></Surfaces></LandXML>
  let terrain = parse(source)
  let inside = sample_elevation(terrain, 0.25, 0.25, surface_name="Ground")
  assert_eq(inside.hits.length(), 1)
  assert_eq(inside.hits[0].elevation, 11.5)
  assert_eq(inside.hits[0].face_number, 1)
  assert_true(sample_elevation(terrain, 0.75, 0.75).hits.is_empty())
  assert_eq(sample_elevation(terrain, 0.5, 0.5).hits[0].elevation, 13.0)
}
