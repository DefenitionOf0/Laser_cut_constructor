import processing.svg.*;
import processing.dxf.*; 
import controlP5.*;
import processing.event.KeyEvent;
import processing.data.*;
import java.io.File;
import java.util.Locale;

ControlP5 cp5;
Accordion accordion; // === NEW: Аккордеон для редактора ===

// ==========================================
// LOCALIZATION GLOBALS
// ==========================================
JSONObject lang;
ArrayList<String> availableLanguages = new ArrayList<String>();
int currentLangIndex = 0;
String currentLangCode = "en";

PFont pUIFont;
ControlFont cFont;

final int STATE_MAIN = 0;
final int STATE_EDITOR = 1;
int appState = STATE_MAIN;

// UI Color Palette
final int COLOR_BG_DARK = color(43, 52, 64);
final int COLOR_BG_LIGHT = color(236, 240, 241);
final int COLOR_PRIMARY = color(52, 152, 219);
final int COLOR_SUCCESS = color(46, 204, 113);
final int COLOR_WARNING = color(230, 126, 34);
final int COLOR_DANGER = color(231, 76, 60);
final int COLOR_PURPLE = color(155, 89, 182);
final int COLOR_WHITE = color(200, 200, 200);
final int COLOR_BLACK = color(0, 0, 0);
final int COLOR_INACTIVE = color(149, 165, 166);
final int COLOR_ENGRAVE = color(52, 73, 94);
final int COLOR_DARK = color(44, 62, 80);

float kerf = 0.2, tabWidth = 15.0, tabDepth = 5.0, snapGap = 2.0;

// CALCULATOR RATES
float rateSetup = 5.0f;
float rateCutPerM = 1.5f;
float rateEngravePerCm2 = 0.5f;
float rateMaterialPerM2 = 20.0f;

// CAMERA
float panX = 0, panY = 0, currentZoom = 5.0;
float mainPanX = 0, mainPanY = 0, mainZoom = 5.0;
float edPanX = 0, edPanY = 0, edZoom = 5.0;

// LIBRARY & SCENE
ArrayList<PartTemplate> library; 
ArrayList<PartInstance> scene;   
ArrayList<PartInstance> clipboard = new ArrayList<PartInstance>(); 

PartTemplate editingPart;
int editingIndex = -1;

SlotLine draggedLine = null, selectedLine = null; 
Cutout draggedCutout = null, selectedCutout = null;
EngraveText draggedText = null, selectedText = null;
EngraveSVG draggedSVG = null, selectedSVG = null;
float dragOffsetX, dragOffsetY;

// SELECTION & DRAGGING
ArrayList<PartInstance> selectedParts = new ArrayList<PartInstance>();
PartInstance leadDragPart = null; 
boolean isSelecting = false;

float selStartX, selStartY, selEndX, selEndY;
float dragMouseStartX, dragMouseStartY; 

// STATE HISTORY (UNDO/REDO)
ArrayList<String> undoStack = new ArrayList<String>();
ArrayList<String> redoStack = new ArrayList<String>();
String stateBeforeDrag = "";
boolean isDraggingPart = false;

// CALCULATOR & EXPORT
float totalSceneCutLength = 0;
boolean doExportDXF = false;

// UI EVENT LOCK
boolean ignoreUIEvents = false;
int selectedLibIndex = 0;

void setup() {
  size(1250, 800, P3D);
  surface.setResizable(true); // === NEW: Разрешаем менять размер окна ===
  
  // Font Initialization
  pUIFont = createFont("Arial", 12, true);
  textFont(pUIFont);
  
  cp5 = new ControlP5(this);
  cFont = new ControlFont(pUIFont, 12);
  cp5.setFont(cFont);

  library = new ArrayList<PartTemplate>(); 
  scene = new ArrayList<PartInstance>();

  setupUI();
  findAvailableLanguages();
  loadPartLibrary();
  
  if (library.size() == 0) {
    PartTemplate startPart = new PartTemplate("Box_Bottom", 100, 100);
    startPart.edges[0]=1; startPart.edges[1]=1; startPart.edges[2]=1; startPart.edges[3]=1;
    library.add(startPart);
    savePartLibrary();
    updateLibraryList();
  }
}

// === NEW: Функция адаптивного интерфейса при ресайзе ===
void windowResized() {
  if (cp5 == null) return;
  // Главный экран
  cp5.getController("btnOpenCalc").setPosition(width - 320, 30);
  cp5.getController("exportBtn").setPosition(width - 150, 30);
  cp5.getController("btnLangSwitch").setPosition(width - 80, 80);
  cp5.getGroup("calcGroup").setPosition(width/2 - 200, height/2 - 250);
  
  cp5.getController("snapGap").setPosition(20, height - 40);
  cp5.getController("in_snapGap").setPosition(150, height - 40);
  
  // Экран редактора
  cp5.getController("saveAndExitBtn").setPosition(20, height - 80);
  cp5.getController("cancelBtn").setPosition(180, height - 80);
  if (accordion != null) {
      accordion.setHeight(height - 180); 
  }
}

void draw() {
  if (doExportDXF) {
    beginRaw(DXF, "laser_cut_project.dxf");
    pushMatrix(); resetMatrix();
    float minX = Float.MAX_VALUE, minY = Float.MAX_VALUE;
    for (PartInstance p : scene) { minX = min(minX, p.getBoundLeft()); minY = min(minY, p.getBoundTop()); }
    translate(-minX + 10, -minY + 10);
    for (PartInstance inst : scene) inst.display(this.g, true, false, false);
    popMatrix(); endRaw(); doExportDXF = false;
  }

  background(245);
  hint(ENABLE_DEPTH_TEST);
  totalSceneCutLength = 0;
  
  // === NEW: Определяем деталь под курсором (Hover) ===
  float wx = (mouseX - panX) / currentZoom;
  float wy = (mouseY - panY) / currentZoom;
  PartInstance hoveredPart = null;
  
  if (appState == STATE_MAIN && !cp5.isMouseOver()) {
      for (int i = scene.size() - 1; i >= 0; i--) {
          if (scene.get(i).contains(wx, wy)) {
              hoveredPart = scene.get(i);
              break;
          }
      }
  }
  
  if (appState == STATE_MAIN) {
    pushMatrix(); translate(panX, panY); scale(currentZoom); drawGrid();
    for (PartInstance inst : scene) {
      boolean isSelected = selectedParts.contains(inst);
      boolean isHovered = (inst == hoveredPart);
      inst.display(this.g, false, isSelected, isHovered); // Передаем hover
      totalSceneCutLength += inst.template.getEstimatePerimeter();
    }
    
    if (isSelecting) {
      pushMatrix(); translate(0, 0, 0.2f);
      fill(52, 152, 219, 50); stroke(52, 152, 219); strokeWeight(1.0f/currentZoom);
      rect(min(selStartX, selEndX), min(selStartY, selEndY), abs(selEndX - selStartX), abs(selEndY - selStartY));
      popMatrix();
    }
    popMatrix();
    
    hint(DISABLE_DEPTH_TEST); 
    noStroke(); fill(COLOR_BG_DARK); rect(0, 0, width, 80);
    fill(255); textSize(20); text(t("ASSEMBLY CANVAS"), 20, 35); 
    fill(180); textSize(12);
    text(t("Drag: Select | R-Click: Pan | Scroll: Zoom | 'Del': Remove | 'R': Rotate | 'Ctrl+C/V': Copy/Paste"), 20, 55);
    fill(255); textSize(16);
    text(t("Total Cut") + ": " + nf(totalSceneCutLength / 1000.0f, 1, 2) + " m", width - 600, 45);
    
  } else if (appState == STATE_EDITOR) {
    background(220, 225, 230); 
    pushMatrix(); translate(panX, panY); scale(currentZoom); drawGrid();
    if (editingPart != null) {
      pushMatrix(); translate(-editingPart.w/2, -editingPart.h/2); 
      editingPart.drawShape(this.g, false, false, false); 
      popMatrix();
    }
    popMatrix();
    
    hint(DISABLE_DEPTH_TEST);
    noStroke(); fill(COLOR_BG_LIGHT); rect(0, 0, 360, height);
    fill(200); rect(360, 0, 1, height);
    fill(COLOR_BG_DARK); rect(0, 0, 360, 50);
    fill(255); textSize(18); text(t("PART EDITOR"), 20, 32);
  }
}

// ==========================================
// LOCALIZATION SYSTEM
// ==========================================
void findAvailableLanguages() {
  availableLanguages.clear();
  File dataFolder = new File(dataPath("")); 
  if (dataFolder.exists() && dataFolder.isDirectory()) {
    File[] files = dataFolder.listFiles();
    if (files != null) {
      for (File f : files) if (f.getName().endsWith(".json")) availableLanguages.add(f.getName().substring(0, f.getName().length() - 5));
    }
  }
  if (availableLanguages.size() > 0) {
    currentLangCode = availableLanguages.get(0); loadLanguage(currentLangCode);
  }
}

void loadLanguage(String code) {
  File f = new File(dataPath(code + ".json"));
  if (f.exists()) { lang = loadJSONObject(code + ".json"); updateUILabels(); }
}

String t(String key) {
  if (lang != null && !lang.isNull(key)) return lang.getString(key);
  return key;
}

void updateUILabels() {
  if (cp5 == null) return;
  ignoreUIEvents = true;
  
  if (cp5.getController("libraryList") != null) cp5.get(ScrollableList.class, "libraryList").setCaptionLabel(t("PART LIBRARY"));
  if (cp5.getController("spawnPartBtn") != null) cp5.getController("spawnPartBtn").setCaptionLabel(t("ADD TO SCENE"));
  if (cp5.getController("openEditorBtn") != null) cp5.getController("openEditorBtn").setCaptionLabel(t("CREATE NEW"));
  if (cp5.getController("editPartBtn") != null) cp5.getController("editPartBtn").setCaptionLabel(t("EDIT PART"));
  if (cp5.getController("deletePartBtn") != null) cp5.getController("deletePartBtn").setCaptionLabel(t("DELETE PART"));
  if (cp5.getController("exportBtn") != null) cp5.getController("exportBtn").setCaptionLabel(t("EXPORT SVG/DXF"));
  if (cp5.getController("snapGap") != null) cp5.getController("snapGap").setCaptionLabel(t("Snap Gap"));
  if (cp5.getController("partName") != null) cp5.getController("partName").setCaptionLabel(t("PART NAME"));
  
  if (cp5.getGroup("gGeom") != null) cp5.getGroup("gGeom").setCaptionLabel(t("GEOMETRY"));
  if (cp5.getGroup("gEdges") != null) cp5.getGroup("gEdges").setCaptionLabel(t("EDGES & SLOTS"));
  if (cp5.getGroup("gEngrave") != null) cp5.getGroup("gEngrave").setCaptionLabel(t("ENGRAVING"));
  if (cp5.getGroup("gTech") != null) cp5.getGroup("gTech").setCaptionLabel(t("TECH SETTINGS"));

  if (cp5.getController("shapeRect") != null) cp5.getController("shapeRect").setCaptionLabel(t("RECTANGLE"));
  if (cp5.getController("shapeCirc") != null) cp5.getController("shapeCirc").setCaptionLabel(t("CIRCLE"));
  if (cp5.getController("shapeTri") != null) cp5.getController("shapeTri").setCaptionLabel(t("TRIANGLE"));
  if (cp5.getController("shapePoly") != null) cp5.getController("shapePoly").setCaptionLabel(t("POLYGON"));
  
  if (editingPart != null && cp5.getController("editWidth") != null) {
    cp5.getController("editWidth").setCaptionLabel(t((editingPart.shapeType == 1 || editingPart.shapeType == 3) ? "Diameter" : "Width"));
  } else if (cp5.getController("editWidth") != null) {
    cp5.getController("editWidth").setCaptionLabel(t("Width"));
  }
  
  if (cp5.getController("editHeight") != null) cp5.getController("editHeight").setCaptionLabel(t("Height"));
  if (cp5.getController("triSideA") != null) cp5.getController("triSideA").setCaptionLabel(t("Side A (Bot)"));
  if (cp5.getController("triSideB") != null) cp5.getController("triSideB").setCaptionLabel(t("Side B (Right)"));
  if (cp5.getController("triSideC") != null) cp5.getController("triSideC").setCaptionLabel(t("Side C (Left)"));
  if (cp5.getController("polySides") != null) cp5.getController("polySides").setCaptionLabel(t("Poly Sides"));
  
  if (cp5.getController("addHSlotBtn") != null) cp5.getController("addHSlotBtn").setCaptionLabel(t("ADD H-SLOT"));
  if (cp5.getController("addVSlotBtn") != null) cp5.getController("addVSlotBtn").setCaptionLabel(t("ADD V-SLOT"));
  if (cp5.getController("addLDSlotBtn") != null) cp5.getController("addLDSlotBtn").setCaptionLabel(t("ADD L-DIAG"));
  if (cp5.getController("addRDSlotBtn") != null) cp5.getController("addRDSlotBtn").setCaptionLabel(t("ADD R-DIAG"));
  if (editingPart != null && cp5.getController("addCSlotBtn") != null) cp5.getController("addCSlotBtn").setCaptionLabel(t(editingPart.shapeType == 3 ? "ADD P-SLOT" : "ADD C-SLOT"));

  if (cp5.getController("addRectCutout") != null) cp5.getController("addRectCutout").setCaptionLabel(t("ADD RECT CUT"));
  if (cp5.getController("addCircCutout") != null) cp5.getController("addCircCutout").setCaptionLabel(t("ADD CIRC CUT"));
  if (cp5.getController("addTextEngraveBtn") != null) cp5.getController("addTextEngraveBtn").setCaptionLabel(t("ADD TEXT"));
  if (cp5.getController("addSvgEngraveBtn") != null) cp5.getController("addSvgEngraveBtn").setCaptionLabel(t("IMPORT SVG"));
  if (cp5.getController("engraveTextInput") != null) cp5.getController("engraveTextInput").setCaptionLabel(t("TEXT"));
  if (cp5.getController("kerf") != null) cp5.getController("kerf").setCaptionLabel(t("Kerf"));
  if (cp5.getController("tabWidth") != null) cp5.getController("tabWidth").setCaptionLabel(t("Tab Size"));
  if (cp5.getController("tabDepth") != null) cp5.getController("tabDepth").setCaptionLabel(t("Mat Depth"));
  if (cp5.getController("saveAndExitBtn") != null) cp5.getController("saveAndExitBtn").setCaptionLabel(t("SAVE TO LIBRARY"));
  if (cp5.getController("cancelBtn") != null) cp5.getController("cancelBtn").setCaptionLabel(t("CANCEL (NO SAVE)"));
  if (cp5.getController("btnLangSwitch") != null) cp5.getController("btnLangSwitch").setCaptionLabel(currentLangCode.toUpperCase());
  
  if (cp5.getController("btnOpenCalc") != null) cp5.getController("btnOpenCalc").setCaptionLabel(t("COST CALCULATOR"));
  if (cp5.getController("btnRecalculate") != null) cp5.getController("btnRecalculate").setCaptionLabel(t("RECALCULATE"));
  if (cp5.getController("btnCloseCalc") != null) cp5.getController("btnCloseCalc").setCaptionLabel(t("CLOSE CALCULATOR"));

  if (editingPart != null) updateEditorButtons();
  ignoreUIEvents = false;
}

public void btnLangSwitch() {
  if (ignoreUIEvents || availableLanguages.size() <= 1) return;
  currentLangIndex++;
  if (currentLangIndex >= availableLanguages.size()) currentLangIndex = 0;
  currentLangCode = availableLanguages.get(currentLangIndex);
  loadLanguage(currentLangCode);
  if (cp5.getGroup("calcGroup").isVisible()) btnRecalculate();
}

// ==========================================
// CALCULATOR & UNDO/REDO (Без изменений)
// ==========================================
public void btnOpenCalc() { btnRecalculate(); cp5.getGroup("calcGroup").show(); cp5.getGroup("calcGroup").bringToFront(); ignoreUIEvents = true; }
public void btnCloseCalc() { cp5.getGroup("calcGroup").hide(); ignoreUIEvents = false; }
public void btnRecalculate() {
  try {
    rateSetup = Float.parseFloat(cp5.get(Textfield.class, "rateSetup").getText().replace(',', '.'));
    rateCutPerM = Float.parseFloat(cp5.get(Textfield.class, "rateCutPerM").getText().replace(',', '.'));
    rateEngravePerCm2 = Float.parseFloat(cp5.get(Textfield.class, "rateEngravePerCm2").getText().replace(',', '.'));
    rateMaterialPerM2 = Float.parseFloat(cp5.get(Textfield.class, "rateMaterialPerM2").getText().replace(',', '.'));
  } catch(Exception e) {}
  float cutLengthM = totalSceneCutLength / 1000.0f; float engraveAreaCm2 = 0;
  float minX = Float.MAX_VALUE, minY = Float.MAX_VALUE, maxX = -Float.MAX_VALUE, maxY = -Float.MAX_VALUE;
  for (PartInstance p : scene) {
    minX = min(minX, p.getBoundLeft()); minY = min(minY, p.getBoundTop());
    maxX = max(maxX, p.getBoundRight()); maxY = max(maxY, p.getBoundBottom());
    for (EngraveText et : p.template.texts) engraveAreaCm2 += ((textWidth(et.text)*(et.size/12.0f)) * et.size) / 100.0f; 
    for (EngraveSVG es : p.template.svgs) engraveAreaCm2 += (es.w * es.h) / 100.0f;
  }
  float matW = max(0, maxX - minX + 20), matH = max(0, maxY - minY + 20);
  float matAreaM2 = (matW * matH) / 1000000.0f; if (scene.isEmpty()) matAreaM2 = 0;
  float costCut = cutLengthM * rateCutPerM, costEngrave = engraveAreaCm2 * rateEngravePerCm2, costMaterial = matAreaM2 * rateMaterialPerM2;
  float finalCost = rateSetup + costCut + costEngrave + costMaterial;
  String report = t("=== JOB ESTIMATE ===") + "\n\n" + t("1. SETUP FEE") + ": $" + nf(rateSetup, 1, 2) + "\n\n" +
    t("2. CUTTING") + " (" + nf(cutLengthM, 1, 2) + " m) : $" + nf(costCut, 1, 2) + "\n   " + t("Rate") + ": $" + rateCutPerM + " / m\n\n" +
    t("3. ENGRAVING") + " (" + nf(engraveAreaCm2, 1, 2) + " cm2) : $" + nf(costEngrave, 1, 2) + "\n   " + t("Rate") + ": $" + rateEngravePerCm2 + " / cm2\n\n" +
    t("4. MATERIAL") + " (" + nf(matAreaM2, 1, 4) + " m2) : $" + nf(costMaterial, 1, 2) + "\n   " + t("Rate") + ": $" + rateMaterialPerM2 + " / m2\n---------------------------------\n" +
    t("TOTAL COST") + ": $" + nf(finalCost, 1, 2);
  cp5.get(Textarea.class, "calcResultsArea").setText(report);
}

void saveState() { undoStack.add(getSnapshot()); if (undoStack.size() > 50) undoStack.remove(0); redoStack.clear(); }
void performUndo() { if (undoStack.size() > 0) { redoStack.add(getSnapshot()); loadSnapshot(undoStack.remove(undoStack.size() - 1)); } }
void performRedo() { if (redoStack.size() > 0) { undoStack.add(getSnapshot()); loadSnapshot(redoStack.remove(redoStack.size() - 1)); } }

String getSnapshot() {
  JSONObject state = new JSONObject(); JSONArray lib = new JSONArray();
  for(int i=0; i<library.size(); i++) {
    PartTemplate t = library.get(i); JSONObject jo = new JSONObject();
    jo.setString("name",t.name); jo.setInt("shape", t.shapeType); jo.setFloat("w",t.w); jo.setFloat("h",t.h); 
    jo.setFloat("triA", t.triA); jo.setFloat("triB", t.triB); jo.setFloat("triC", t.triC); jo.setInt("polySides", t.polySides);
    JSONArray ea=new JSONArray(); for(int j=0;j<4;j++) ea.setInt(j,t.edges[j]); jo.setJSONArray("edges",ea); 
    JSONArray sla=new JSONArray(); for (SlotLine sl : t.slotLines) { JSONObject slo = new JSONObject(); slo.setInt("dir",sl.dir); slo.setFloat("pos",sl.pos); sla.append(slo); } jo.setJSONArray("slotLines", sla); 
    JSONArray cutA=new JSONArray(); for (Cutout c : t.cutouts) { JSONObject co = new JSONObject(); co.setInt("type",c.type); co.setFloat("x",c.x); co.setFloat("y",c.y); co.setFloat("w",c.w); co.setFloat("h",c.h); cutA.append(co); } jo.setJSONArray("cutouts", cutA); 
    JSONArray txtA = new JSONArray(); for(EngraveText et : t.texts) { JSONObject txtObj = new JSONObject(); txtObj.setFloat("x", et.x); txtObj.setFloat("y", et.y); txtObj.setString("t", et.text); txtObj.setFloat("s", et.size); txtA.append(txtObj); } jo.setJSONArray("texts", txtA);
    JSONArray svgA = new JSONArray(); for(EngraveSVG es : t.svgs) { JSONObject svgO = new JSONObject(); svgO.setFloat("x", es.x); svgO.setFloat("y", es.y); svgO.setFloat("w", es.w); svgO.setFloat("h", es.h); svgO.setString("p", es.filepath); svgA.append(svgO); } jo.setJSONArray("svgs", svgA);
    lib.append(jo); 
  }
  state.setJSONArray("library", lib);
  JSONArray scn = new JSONArray();
  for(PartInstance p : scene) { JSONObject po = new JSONObject(); po.setInt("templateIndex", library.indexOf(p.template)); po.setFloat("x", p.x); po.setFloat("y", p.y); po.setInt("rot", p.rot); scn.append(po); }
  state.setJSONArray("scene", scn); return state.toString();
}

void loadSnapshot(String jsonString) {
  ignoreUIEvents = true; JSONObject state = parseJSONObject(jsonString);
  JSONArray lib = state.getJSONArray("library"); library.clear();
  for(int i=0;i<lib.size();i++) {
    JSONObject jo=lib.getJSONObject(i); PartTemplate t=new PartTemplate(jo.getString("name"),jo.getFloat("w"),jo.getFloat("h"));
    if(!jo.isNull("shape")) t.shapeType = jo.getInt("shape"); 
    if(!jo.isNull("triA")) { t.triA=jo.getFloat("triA"); t.triB=jo.getFloat("triB"); t.triC=jo.getFloat("triC"); }
    if(!jo.isNull("polySides")) t.polySides = jo.getInt("polySides");
    if(t.shapeType == 2) t.validateTriangle(); if(t.shapeType == 3) t.validatePolygon();
    JSONArray ea=jo.getJSONArray("edges"); for(int j=0;j<4;j++) t.edges[j]=ea.getInt(j); 
    if (!jo.isNull("slotLines")) { JSONArray sla = jo.getJSONArray("slotLines"); for (int k=0; k<sla.size(); k++) { JSONObject slo = sla.getJSONObject(k); t.slotLines.add(new SlotLine(slo.getInt("dir"),slo.getFloat("pos"))); } } 
    if (!jo.isNull("cutouts")) { JSONArray cutA = jo.getJSONArray("cutouts"); for (int k=0; k<cutA.size(); k++) { JSONObject c = cutA.getJSONObject(k); t.cutouts.add(new Cutout(c.getInt("type"),c.getFloat("x"),c.getFloat("y"),c.getFloat("w"),c.getFloat("h"))); } } 
    if (!jo.isNull("texts")) { JSONArray txtA = jo.getJSONArray("texts"); for (int k=0; k<txtA.size(); k++) { JSONObject txtObj = txtA.getJSONObject(k); t.texts.add(new EngraveText(txtObj.getString("t"), txtObj.getFloat("x"), txtObj.getFloat("y"), txtObj.getFloat("s"))); } }
    if (!jo.isNull("svgs")) { JSONArray svgA = jo.getJSONArray("svgs"); for (int k=0; k<svgA.size(); k++) { JSONObject so = svgA.getJSONObject(k); t.svgs.add(new EngraveSVG(so.getString("p"), so.getFloat("x"), so.getFloat("y"), so.getFloat("w"), so.getFloat("h"))); } }
    library.add(t);
  }
  JSONArray scn = state.getJSONArray("scene"); scene.clear(); selectedParts.clear(); leadDragPart = null;
  for(int i=0; i<scn.size(); i++) {
    JSONObject po = scn.getJSONObject(i); int tIdx = po.getInt("templateIndex");
    if (tIdx >= 0 && tIdx < library.size()) { PartInstance p = new PartInstance(library.get(tIdx), po.getFloat("x"), po.getFloat("y")); p.rot = po.getInt("rot"); scene.add(p); }
  }
  updateLibraryList(); ignoreUIEvents = false;
}

// ==========================================
// CAMERA & MOUSE INTERACTION
// ==========================================
void mouseWheel(MouseEvent event) {
  if (cp5.isMouseOver()) return; 
  float zf = (event.getCount() > 0) ? 0.9 : 1.1; 
  float wx = (mouseX - panX) / currentZoom, wy = (mouseY - panY) / currentZoom;
  currentZoom = constrain(currentZoom * zf, 0.5, 30.0); 
  panX = mouseX - wx * currentZoom; panY = mouseY - wy * currentZoom;
}

void mousePressed() {
  if (cp5.isMouseOver()) return;
  float wx = (mouseX - panX) / currentZoom, wy = (mouseY - panY) / currentZoom;
  
  if (appState == STATE_MAIN && mouseButton == LEFT) {
    boolean clicked = false;
    for (int i = scene.size() - 1; i >= 0; i--) {
      PartInstance p = scene.get(i);
      if (p.contains(wx, wy)) {
        clicked = true; leadDragPart = p;
        if (!selectedParts.contains(p)) { selectedParts.clear(); selectedParts.add(p); }
        isDraggingPart = false; stateBeforeDrag = getSnapshot();
        dragMouseStartX = wx; dragMouseStartY = wy;
        for (PartInstance sp : selectedParts) { sp.dragStartX = sp.x; sp.dragStartY = sp.y; }
        break;
      }
    }
    if (!clicked) { selectedParts.clear(); leadDragPart = null; isSelecting = true; selStartX=wx; selStartY=wy; selEndX=wx; selEndY=wy; }
  } 
  else if (appState == STATE_EDITOR && mouseButton == LEFT) {
    float px = -editingPart.w/2, py = -editingPart.h/2; float lx = wx - px, ly = wy - py;
    selectedLine = null; selectedCutout = null; selectedText = null; selectedSVG = null; clearPropertiesUI();
    boolean found = false;
    
    for (int i = editingPart.svgs.size() - 1; i >= 0; i--) {
        EngraveSVG es = editingPart.svgs.get(i);
        if (lx >= es.x - es.w/2 && lx <= es.x + es.w/2 && ly >= es.y - es.h/2 && ly <= es.y + es.h/2) {
            draggedSVG = es; selectedSVG = es; dragOffsetX = lx - es.x; dragOffsetY = ly - es.y; found = true; 
            populatePropertiesUI(es.x, es.y, es.w, es.h); break;
        }
    }
    if (!found) {
        for (int i = editingPart.texts.size() - 1; i >= 0; i--) {
            EngraveText et = editingPart.texts.get(i); float tw = textWidth(et.text) * (et.size / 12.0f); float th = et.size;
            if (lx >= et.x - tw/2 && lx <= et.x + tw/2 && ly >= et.y - th/2 && ly <= et.y + th/2) {
                draggedText = et; selectedText = et; dragOffsetX = lx - et.x; dragOffsetY = ly - et.y; found = true; 
                populatePropertiesUI(et.x, et.y, 0, et.size); cp5.get(Textfield.class, "engraveTextInput").setText(et.text); break;
            }
        }
    }
    if (!found) {
        for (int i = editingPart.cutouts.size() - 1; i >= 0; i--) {
          Cutout c = editingPart.cutouts.get(i);
          if (lx >= c.x - c.w/2 && lx <= c.x + c.w/2 && ly >= c.y - c.h/2 && ly <= c.y + c.h/2) {
            draggedCutout = c; selectedCutout = c; dragOffsetX = lx - c.x; dragOffsetY = ly - c.y; found = true; 
            populatePropertiesUI(c.x, c.y, c.w, c.h); break;
          }
        }
    }
    if (!found) {
      float cr = 8.0 / currentZoom;
      for (SlotLine line : editingPart.slotLines) {
        if (line.dir == 2) { 
            if (editingPart.shapeType == 1) { 
                float distToCenter = dist(lx, ly, editingPart.w/2, editingPart.h/2);
                if (abs(distToCenter - line.pos) < cr) { draggedLine = line; selectedLine = line; dragOffsetX = lx; dragOffsetY = ly; line.startDragPos = line.pos; found = true; break; }
            } else if (editingPart.shapeType == 3) { 
                float cx = editingPart.w/2, cy = editingPart.h/2; float aStep = TWO_PI / editingPart.polySides; boolean clickedRing = false;
                for (int j = 0; j < editingPart.polySides; j++) {
                    float a1 = j * aStep - HALF_PI, a2 = (j+1) * aStep - HALF_PI;
                    float p1x = cx + line.pos * cos(a1), p1y = cy + line.pos * sin(a1), p2x = cx + line.pos * cos(a2), p2y = cy + line.pos * sin(a2);
                    if (distToSegment(lx, ly, p1x, p1y, p2x, p2y) < cr) { clickedRing = true; break; }
                }
                if (clickedRing) { draggedLine = line; selectedLine = line; dragOffsetX = lx; dragOffsetY = ly; line.startDragPos = line.pos; found = true; break; }
            }
        } else {
            if (line.lx1 == line.lx2 && line.ly1 == line.ly2) continue;
            if (distToSegment(lx, ly, line.lx1, line.ly1, line.lx2, line.ly2) < cr) { draggedLine = line; selectedLine = line; dragOffsetX = lx; dragOffsetY = ly; line.startDragPos = line.pos; found = true; break; }
        }
      }
      if (found) cp5.get(Textfield.class, "slotPosInput").setText(nf(selectedLine.pos, 1, 2).replace(',','.'));
    }
  }
}

void clearPropertiesUI() { cp5.get(Textfield.class, "objX").setText(""); cp5.get(Textfield.class, "objY").setText(""); cp5.get(Textfield.class, "objW").setText(""); cp5.get(Textfield.class, "objH").setText(""); }
void populatePropertiesUI(float x, float y, float w, float h) {
    cp5.get(Textfield.class, "objX").setText(nf(x, 1, 1).replace(',','.')); cp5.get(Textfield.class, "objY").setText(nf(y, 1, 1).replace(',','.'));
    if (w > 0) cp5.get(Textfield.class, "objW").setText(nf(w, 1, 2).replace(',','.')); if (h > 0) cp5.get(Textfield.class, "objH").setText(nf(h, 1, 2).replace(',','.'));
}
float distToSegment(float px, float py, float x1, float y1, float x2, float y2) {
  float l2 = dist(x1, y1, x2, y2); l2 *= l2; if (l2 == 0) return dist(px, py, x1, y1);
  float t = max(0, min(1, ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2)); return dist(px, py, x1 + t * (x2 - x1), y1 + t * (y2 - y1));
}

void mouseDragged() {
  if (cp5.isMouseOver()) return;
  float wx = (mouseX - panX) / currentZoom, wy = (mouseY - panY) / currentZoom;
  if (mouseButton == RIGHT || mouseButton == CENTER) { panX += mouseX - pmouseX; panY += mouseY - pmouseY; return; }

  if (appState == STATE_MAIN && mouseButton == LEFT) {
    if (isSelecting) { selEndX = wx; selEndY = wy; } 
    else if (leadDragPart != null) {
      isDraggingPart = true;
      leadDragPart.x = leadDragPart.dragStartX + (wx - dragMouseStartX);
      leadDragPart.y = leadDragPart.dragStartY + (wy - dragMouseStartY);
      
      float snapD = 10.0 / currentZoom; 
      for (PartInstance other : scene) {
        if (selectedParts.contains(other)) continue;
        float dL=leadDragPart.getBoundLeft(), dR=leadDragPart.getBoundRight(), dT=leadDragPart.getBoundTop(), dB=leadDragPart.getBoundBottom();
        float oL=other.getBoundLeft(), oR=other.getBoundRight(), oT=other.getBoundTop(), oB=other.getBoundBottom();
        float aY = abs(leadDragPart.y - other.y), aX = abs(leadDragPart.x - other.x);
        if (aY < 20.0 / currentZoom) {
          if (abs((dR + snapGap) - oL) < snapD) { leadDragPart.x += (oL - snapGap) - dR; leadDragPart.y = other.y; break; }
          if (abs((dL - snapGap) - oR) < snapD) { leadDragPart.x += (oR + snapGap) - dL; leadDragPart.y = other.y; break; }
        }
        if (aX < 20.0 / currentZoom) {
          if (abs((dB + snapGap) - oT) < snapD) { leadDragPart.y += (oT - snapGap) - dB; leadDragPart.x = other.x; break; }
          if (abs((dT - snapGap) - oB) < snapD) { leadDragPart.y += (oB + snapGap) - dT; leadDragPart.x = other.x; break; }
        }
      }
      float finalDx = leadDragPart.x - leadDragPart.dragStartX, finalDy = leadDragPart.y - leadDragPart.dragStartY;
      for (PartInstance p : selectedParts) if (p != leadDragPart) { p.x = p.dragStartX + finalDx; p.y = p.dragStartY + finalDy; }
    }
  } 
  else if (appState == STATE_EDITOR) {
    float lx = wx - (-editingPart.w/2), ly = wy - (-editingPart.h/2);
    if (draggedCutout != null) {
      draggedCutout.x = lx - dragOffsetX; draggedCutout.y = ly - dragOffsetY;
      cp5.get(Textfield.class, "objX").setText(nf(draggedCutout.x, 1, 1).replace(',','.')); cp5.get(Textfield.class, "objY").setText(nf(draggedCutout.y, 1, 1).replace(',','.'));
    } else if (draggedText != null) {
      draggedText.x = lx - dragOffsetX; draggedText.y = ly - dragOffsetY;
      cp5.get(Textfield.class, "objX").setText(nf(draggedText.x, 1, 1).replace(',','.')); cp5.get(Textfield.class, "objY").setText(nf(draggedText.y, 1, 1).replace(',','.'));
    } else if (draggedSVG != null) {
      draggedSVG.x = lx - dragOffsetX; draggedSVG.y = ly - dragOffsetY;
      cp5.get(Textfield.class, "objX").setText(nf(draggedSVG.x, 1, 1).replace(',','.')); cp5.get(Textfield.class, "objY").setText(nf(draggedSVG.y, 1, 1).replace(',','.'));
    } else if (draggedLine != null) {
      float rDx = lx - dragOffsetX, rDy = ly - dragOffsetY;
      if (draggedLine.dir == 0) draggedLine.pos = constrain(draggedLine.startDragPos + rDy, 0, editingPart.h);
      else if (draggedLine.dir == 1) draggedLine.pos = constrain(draggedLine.startDragPos + rDx, 0, editingPart.w);
      else if (draggedLine.dir == 2) {
          float iR = dist(dragOffsetX, dragOffsetY, editingPart.w/2, editingPart.h/2), nR = dist(lx, ly, editingPart.w/2, editingPart.h/2);
          draggedLine.pos = constrain(draggedLine.startDragPos + (nR - iR), 1, min(editingPart.w, editingPart.h)/2);
      }
      else if (draggedLine.dir == 3 || draggedLine.dir == 4) {
          float delta = (draggedLine.dir == 3) ? rDx : -rDx; draggedLine.pos = constrain(draggedLine.startDragPos + delta, 0, max(editingPart.w, editingPart.h));
      }
      cp5.get(Textfield.class, "slotPosInput").setText(nf(draggedLine.pos, 1, 2).replace(',','.'));
    }
  }
}

void mouseReleased() { 
  if (isSelecting) {
    float rx1=min(selStartX, selEndX), rx2=max(selStartX, selEndX), ry1=min(selStartY, selEndY), ry2=max(selStartY, selEndY);
    selectedParts.clear();
    for (PartInstance p : scene) if (p.x >= rx1 && p.x + p.getRealW() <= rx2 && p.y >= ry1 && p.y + p.getRealH() <= ry2) selectedParts.add(p);
    isSelecting = false;
  }
  if (appState == STATE_MAIN && isDraggingPart) { undoStack.add(stateBeforeDrag); redoStack.clear(); isDraggingPart = false; }
  leadDragPart = null; draggedLine = null; draggedCutout = null; draggedText = null; draggedSVG = null;
}

// ==========================================
// KEYBOARD & UI EVENTS
// ==========================================
void keyPressed(KeyEvent e) {
  boolean isTyping = false;
  for (ControllerInterface<?> c : cp5.getAll()) if (c instanceof Textfield && ((Textfield)c).isFocus()) isTyping = true;
  if (isTyping) return;
  
  if ((e.isControlDown() || e.isMetaDown()) && (keyCode == 'Z' || keyCode == 'z')) { performUndo(); return; }
  if ((e.isControlDown() || e.isMetaDown()) && (keyCode == 'Y' || keyCode == 'y')) { performRedo(); return; }
  
  if (appState == STATE_MAIN) {
    if (key == DELETE || key == BACKSPACE) { if (selectedParts.size() > 0) saveState(); scene.removeAll(selectedParts); selectedParts.clear(); }
    if (key == 'r' || key == 'R') { if (selectedParts.size() > 0) saveState(); for (PartInstance p : selectedParts) p.rot = (p.rot + 1) % 4; }
    if ((e.isControlDown() || e.isMetaDown()) && (keyCode == 'C' || keyCode == 'c')) {
      clipboard.clear(); for (PartInstance p : selectedParts) { PartInstance copy = new PartInstance(p.template, p.x, p.y); copy.rot = p.rot; clipboard.add(copy); }
    }
    if ((e.isControlDown() || e.isMetaDown()) && (keyCode == 'V' || keyCode == 'v') && clipboard.size() > 0) {
      saveState(); selectedParts.clear();
      float wx = (mouseX - panX) / currentZoom, wy = (mouseY - panY) / currentZoom;
      float ox = wx - clipboard.get(0).x, oy = wy - clipboard.get(0).y;
      for (PartInstance p : clipboard) { PartInstance clone = new PartInstance(p.template, p.x + ox, p.y + oy); clone.rot = p.rot; scene.add(clone); selectedParts.add(clone); }
    }
  } else if (appState == STATE_EDITOR) {
    if (key == DELETE || key == BACKSPACE) {
      if (selectedLine != null) { editingPart.slotLines.remove(selectedLine); selectedLine = null; cp5.get(Textfield.class, "slotPosInput").setText(""); }
      if (selectedCutout != null) { editingPart.cutouts.remove(selectedCutout); selectedCutout = null; clearPropertiesUI(); }
      if (selectedText != null) { editingPart.texts.remove(selectedText); selectedText = null; clearPropertiesUI(); }
      if (selectedSVG != null) { editingPart.svgs.remove(selectedSVG); selectedSVG = null; clearPropertiesUI(); }
    }
  }
}

void controlEvent(ControlEvent e) {
  if (ignoreUIEvents) return;
  if (e.isController()) {
    String n = e.getController().getName();
    if (n.equals("editWidth") || n.equals("editHeight") || n.equals("kerf") || n.equals("tabWidth") || n.equals("tabDepth") || 
        n.equals("snapGap") || n.startsWith("triSide") || n.equals("polySides")) {
      float v = e.getController().getValue();
      cp5.get(Textfield.class, "in_" + n).setText(nf(v, 1, 2).replace(',', '.'));
      
      if (editingPart != null) {
        if (n.equals("editWidth")) { 
            editingPart.w = v;
            if (editingPart.shapeType == 3 || editingPart.shapeType == 1) editingPart.h = v;
            if(editingPart.shapeType == 3) editingPart.validatePolygon();
        }
        else if (n.equals("editHeight")) editingPart.h = v;
        else if (n.equals("triSideA")) { editingPart.triA = v; editingPart.validateTriangle(); syncTriSliders(); }
        else if (n.equals("triSideB")) { editingPart.triB = v; editingPart.validateTriangle(); syncTriSliders(); }
        else if (n.equals("triSideC")) { editingPart.triC = v; editingPart.validateTriangle(); syncTriSliders(); }
        else if (n.equals("polySides")) { editingPart.polySides = max(3, (int)v); }
      } else if (n.equals("snapGap")) snapGap = v; else if (n.equals("kerf")) kerf = v;
      else if (n.equals("tabWidth")) tabWidth = v; else if (n.equals("tabDepth")) tabDepth = v;
    }
    else if (n.startsWith("in_")) {
      String sliderName = n.substring(3);
      try { float val = Float.parseFloat(e.getStringValue().replace(',', '.')); cp5.get(Slider.class, sliderName).setValue(val); } catch(Exception ex) {}
    }
    else if (n.equals("objX")) { 
        try { float val = Float.parseFloat(e.getStringValue().replace(',', '.'));
        if (selectedCutout != null) selectedCutout.x = val; else if (selectedText != null) selectedText.x = val;
        else if (selectedSVG != null) selectedSVG.x = val; } catch(Exception ex){} 
    }
    else if (n.equals("objY")) { 
        try { float val = Float.parseFloat(e.getStringValue().replace(',', '.'));
        if (selectedCutout != null) selectedCutout.y = val; else if (selectedText != null) selectedText.y = val;
        else if (selectedSVG != null) selectedSVG.y = val; } catch(Exception ex){} 
    }
    else if (n.equals("objW")) { 
        try { float val = max(1, Float.parseFloat(e.getStringValue().replace(',', '.')));
            if (selectedCutout != null) selectedCutout.w = val; 
            else if (selectedSVG != null) { selectedSVG.w = val; selectedSVG.h = val / selectedSVG.aspect; cp5.get(Textfield.class, "objH").setText(nf(selectedSVG.h, 1, 2).replace(',','.')); }
        } catch(Exception ex){} 
    }
    else if (n.equals("objH")) { 
        try { float val = max(1, Float.parseFloat(e.getStringValue().replace(',', '.')));
            if (selectedCutout != null) selectedCutout.h = val; 
            else if (selectedText != null) selectedText.size = val;
            else if (selectedSVG != null) { selectedSVG.h = val; selectedSVG.w = val * selectedSVG.aspect; cp5.get(Textfield.class, "objW").setText(nf(selectedSVG.w, 1, 2).replace(',','.')); }
        } catch(Exception ex){} 
    }
    else if (n.equals("engraveTextInput") && selectedText != null) { selectedText.text = e.getStringValue(); }
    else if (n.equals("slotPosInput") && selectedLine != null && editingPart != null) {
      try { float val = Float.parseFloat(e.getStringValue().replace(',', '.')); selectedLine.pos = val; } catch(Exception ex){}
    }
  }
}

void syncTriSliders() {
    ignoreUIEvents = true;
    cp5.getController("triSideA").setValue(editingPart.triA); cp5.get(Textfield.class, "in_triSideA").setText(nf(editingPart.triA, 1, 2).replace(',','.'));
    cp5.getController("triSideB").setValue(editingPart.triB); cp5.get(Textfield.class, "in_triSideB").setText(nf(editingPart.triB, 1, 2).replace(',','.'));
    cp5.getController("triSideC").setValue(editingPart.triC); cp5.get(Textfield.class, "in_triSideC").setText(nf(editingPart.triC, 1, 2).replace(',','.'));
    ignoreUIEvents = false;
}

// ==========================================
// UI SETUP
// ==========================================
void setupUI() {
  Tooltip tooltip = cp5.getTooltip();
  tooltip.setDelay(400); // === NEW: Настройка Tooltip ===

  Group mGrp = cp5.addGroup("mainGroup").setPosition(0, 0).hideBar();
  cp5.addScrollableList("libraryList").setPosition(20, 90).setSize(200, 250).setGroup(mGrp).setBarHeight(35).setItemHeight(30).setCaptionLabel("PART LIBRARY").close().setColorBackground(COLOR_BG_DARK).setColorForeground(COLOR_PRIMARY);
  cp5.addButton("spawnPartBtn").setPosition(240, 90).setSize(120, 35).setGroup(mGrp).setCaptionLabel("ADD TO SCENE").setColorBackground(COLOR_SUCCESS);
  cp5.addButton("openEditorBtn").setPosition(370, 90).setSize(120, 35).setGroup(mGrp).setCaptionLabel("CREATE NEW").setColorBackground(COLOR_PRIMARY);
  cp5.addButton("editPartBtn").setPosition(500, 90).setSize(120, 35).setGroup(mGrp).setCaptionLabel("EDIT PART").setColorBackground(COLOR_PURPLE);
  cp5.addButton("deletePartBtn").setPosition(630, 90).setSize(120, 35).setGroup(mGrp).setCaptionLabel("DELETE PART").setColorBackground(COLOR_DANGER);
  
  cp5.addButton("btnOpenCalc").setPosition(width - 320, 30).setSize(150, 35).setGroup(mGrp).setCaptionLabel("COST CALCULATOR").setColorBackground(COLOR_WARNING);
  cp5.addButton("exportBtn").setPosition(width - 150, 30).setSize(120, 35).setGroup(mGrp).setCaptionLabel("EXPORT SVG/DXF").setColorBackground(COLOR_SUCCESS);
  
  createSliderWithInput(mGrp, "snapGap", "Snap Gap", 20, height - 40, 0, 30, 2.0);
  tooltip.register("snapGap", "Magnetic snap distance between parts on canvas");
  
  cp5.addButton("btnLangSwitch").setPosition(width - 80, 80).setSize(60, 30).setCaptionLabel("EN").setColorBackground(COLOR_PURPLE);

  // COST CALCULATOR WINDOW (MODAL)
  Group cGrp = cp5.addGroup("calcGroup").setPosition(width/2 - 200, height/2 - 250).setSize(400, 500).setBackgroundColor(color(43, 52, 64, 240)).setBarHeight(40).setCaptionLabel("PROFESSIONAL COST CALCULATOR").hide();
  int cy = 20;
  cp5.addTextfield("rateSetup").setPosition(20, cy).setSize(80, 25).setGroup(cGrp).setCaptionLabel("SETUP FEE ($)").setText(str(rateSetup)).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_WARNING).setColorValueLabel(0);
  cp5.addTextfield("rateCutPerM").setPosition(120, cy).setSize(80, 25).setGroup(cGrp).setCaptionLabel("CUT / M ($)").setText(str(rateCutPerM)).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_WARNING).setColorValueLabel(0);
  cp5.addTextfield("rateEngravePerCm2").setPosition(220, cy).setSize(80, 25).setGroup(cGrp).setCaptionLabel("ENGRAVE / CM2 ($)").setText(str(rateEngravePerCm2)).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_WARNING).setColorValueLabel(0);
  cp5.addTextfield("rateMaterialPerM2").setPosition(320, cy).setSize(80, 25).setGroup(cGrp).setCaptionLabel("MATERIAL / M2 ($)").setText(str(rateMaterialPerM2)).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_WARNING).setColorValueLabel(0);
  cy += 70; cp5.addButton("btnRecalculate").setPosition(20, cy).setSize(360, 30).setGroup(cGrp).setCaptionLabel("RECALCULATE").setColorBackground(COLOR_PRIMARY);
  cy += 50; cp5.addTextarea("calcResultsArea").setPosition(20, cy).setSize(360, 250).setGroup(cGrp).setFont(cFont).setLineHeight(24).setColor(color(255)).setColorBackground(color(0, 50)).setBorderColor(color(100));
  cy += 270; cp5.addButton("btnCloseCalc").setPosition(20, cy).setSize(360, 35).setGroup(cGrp).setCaptionLabel("CLOSE CALCULATOR").setColorBackground(COLOR_DANGER);

  // === NEW: СБОРКА РЕДАКТОРА С ACCORDION ===
  Group eGrp = cp5.addGroup("editorGroup").setPosition(0, 0).hideBar().hide();
  
  cp5.addTextfield("partName").setPosition(20, 60).setSize(200, 25).setGroup(eGrp).setCaptionLabel("PART NAME").setText("New Part").setColorCaptionLabel(0).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_PRIMARY).setColorValueLabel(0);

  // ГРУППА 1: ГЕОМЕТРИЯ
  Group gGeom = cp5.addGroup("gGeom").setCaptionLabel("GEOMETRY").setBackgroundColor(color(43,52,64,200)).setHeight(25);
  int ay = 10;
  cp5.addButton("shapeRect").setPosition(10, ay).setSize(70, 25).setGroup(gGeom).setCaptionLabel("RECTANGLE").setColorBackground(COLOR_PRIMARY);
  cp5.addButton("shapeCirc").setPosition(85, ay).setSize(70, 25).setGroup(gGeom).setCaptionLabel("CIRCLE").setColorBackground(COLOR_INACTIVE);
  cp5.addButton("shapeTri").setPosition(160, ay).setSize(70, 25).setGroup(gGeom).setCaptionLabel("TRIANGLE").setColorBackground(COLOR_INACTIVE);
  cp5.addButton("shapePoly").setPosition(235, ay).setSize(70, 25).setGroup(gGeom).setCaptionLabel("POLYGON").setColorBackground(COLOR_INACTIVE);
  ay += 35;
  createSliderWithInput(gGeom, "editWidth", "Width", 10, ay, 20, 400, 100); ay += 30;
  createSliderWithInput(gGeom, "editHeight", "Height", 10, ay, 20, 400, 100); ay += 30;
  createSliderWithInput(gGeom, "triSideA", "Side A (Bot)", 10, ay-60, 20, 400, 100);
  createSliderWithInput(gGeom, "triSideB", "Side B (Right)", 10, ay-30, 20, 400, 100);
  createSliderWithInput(gGeom, "triSideC", "Side C (Left)", 10, ay, 20, 400, 100); ay += 30;
  createSliderWithInput(gGeom, "polySides", "Poly Sides", 10, ay-30, 3, 12, 5);

  // ГРУППА 2: КРАЯ И ПАЗЫ
  Group gEdges = cp5.addGroup("gEdges").setCaptionLabel("EDGES & SLOTS").setBackgroundColor(color(43,52,64,200)).setHeight(25);
  ay = 10;
  cp5.addButton("toggleTop").setPosition(10, ay).setSize(140, 20).setGroup(gEdges).setCaptionLabel("TOP: FLAT").setColorBackground(COLOR_DARK); ay += 25;
  cp5.addButton("toggleRight").setPosition(10, ay).setSize(140, 20).setGroup(gEdges).setCaptionLabel("RIGHT: FLAT").setColorBackground(COLOR_DARK); ay += 25;
  cp5.addButton("toggleBottom").setPosition(10, ay).setSize(140, 20).setGroup(gEdges).setCaptionLabel("BOTTOM: FLAT").setColorBackground(COLOR_DARK); ay += 25;
  cp5.addButton("toggleLeft").setPosition(10, ay).setSize(140, 20).setGroup(gEdges).setCaptionLabel("LEFT: FLAT").setColorBackground(COLOR_DARK); ay += 30;
  
  cp5.addButton("addHSlotBtn").setPosition(10, ay).setSize(75, 25).setGroup(gEdges).setCaptionLabel("ADD H-SLOT").setColorBackground(COLOR_WARNING);
  cp5.addButton("addVSlotBtn").setPosition(90, ay).setSize(75, 25).setGroup(gEdges).setCaptionLabel("ADD V-SLOT").setColorBackground(COLOR_WARNING);
  cp5.addButton("addCSlotBtn").setPosition(170, ay).setSize(75, 25).setGroup(gEdges).setCaptionLabel("ADD C-SLOT").setColorBackground(COLOR_WARNING).hide();
  cp5.addButton("addLDSlotBtn").setPosition(90, ay).setSize(75, 25).setGroup(gEdges).setCaptionLabel("ADD L-DIAG").setColorBackground(COLOR_WARNING).hide();
  cp5.addButton("addRDSlotBtn").setPosition(170, ay).setSize(75, 25).setGroup(gEdges).setCaptionLabel("ADD R-DIAG").setColorBackground(COLOR_WARNING).hide();
  cp5.addTextfield("slotPosInput").setPosition(250, ay).setSize(50, 25).setGroup(gEdges).setCaptionLabel("").setColorCaptionLabel(0).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_WARNING).setColorValueLabel(0).setAutoClear(false);
  tooltip.register("slotPosInput", "Position offset for the selected slot line");

  // ГРУППА 3: ГРАВИРОВКА И ВЫРЕЗЫ
  Group gEngrave = cp5.addGroup("gEngrave").setCaptionLabel("ENGRAVING").setBackgroundColor(color(43,52,64,200)).setHeight(25);
  ay = 10;
  cp5.addButton("addRectCutout").setPosition(10, ay).setSize(110, 25).setGroup(gEngrave).setCaptionLabel("ADD RECT CUT").setColorBackground(COLOR_PURPLE);
  cp5.addButton("addCircCutout").setPosition(130, ay).setSize(110, 25).setGroup(gEngrave).setCaptionLabel("ADD CIRC CUT").setColorBackground(COLOR_PURPLE); ay += 35;
  cp5.addButton("addTextEngraveBtn").setPosition(10, ay).setSize(110, 25).setGroup(gEngrave).setCaptionLabel("ADD TEXT").setColorBackground(COLOR_ENGRAVE);
  cp5.addButton("addSvgEngraveBtn").setPosition(130, ay).setSize(110, 25).setGroup(gEngrave).setCaptionLabel("IMPORT SVG").setColorBackground(COLOR_ENGRAVE); ay += 35;
  cp5.addTextfield("engraveTextInput").setPosition(10, ay).setSize(230, 25).setGroup(gEngrave).setCaptionLabel("TEXT").setText("Happy birthday").setColorCaptionLabel(0).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_ENGRAVE).setColorValueLabel(0); ay += 45;
  cp5.addTextfield("objX").setPosition(10, ay).setSize(45, 25).setGroup(gEngrave).setCaptionLabel("X").setAutoClear(false).setColorLabel(COLOR_WHITE).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_PURPLE).setColorValueLabel(COLOR_BLACK);
  cp5.addTextfield("objY").setPosition(65, ay).setSize(45, 25).setGroup(gEngrave).setCaptionLabel("Y").setAutoClear(false).setColorLabel(COLOR_WHITE).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_PURPLE).setColorValueLabel(COLOR_BLACK);
  cp5.addTextfield("objW").setPosition(120, ay).setSize(45, 25).setGroup(gEngrave).setCaptionLabel("W").setAutoClear(false).setColorLabel(COLOR_WHITE).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_PURPLE).setColorValueLabel(COLOR_BLACK);
  cp5.addTextfield("objH").setPosition(175, ay).setSize(45, 25).setGroup(gEngrave).setCaptionLabel("H/Size").setAutoClear(false).setColorLabel(COLOR_WHITE).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_PURPLE).setColorValueLabel(COLOR_BLACK);

  // ГРУППА 4: НАСТРОЙКИ СТАНКА (TECH)
  Group gTech = cp5.addGroup("gTech").setCaptionLabel("TECH SETTINGS").setBackgroundColor(color(43,52,64,200)).setHeight(25);
  ay = 10;
  createSliderWithInput(gTech, "kerf", "Kerf", 10, ay, 0, 1.0, 0.2); ay += 30;
  createSliderWithInput(gTech, "tabWidth", "Tab Size", 10, ay, 5, 50, 15.0); ay += 30;
  createSliderWithInput(gTech, "tabDepth", "Mat Depth", 10, ay, 1, 10, 5.0);
  
  tooltip.register("kerf", "Laser beam width compensation");
  tooltip.register("tabDepth", "Material thickness for tab connections");

  // Собираем всё в Аккордеон
  accordion = cp5.addAccordion("acc")
                 .setPosition(10, 110)
                 .setWidth(340)
                 .setHeight(height - 180) // Ограничиваем высоту для скролла
                 .addItem(gGeom)
                 .addItem(gEdges)
                 .addItem(gEngrave)
                 .addItem(gTech);
  accordion.setCollapseMode(Accordion.MULTI);
  accordion.open(0, 1); // По умолчанию открываем первые две вкладки
  
  // Кнопки сохранения (остаются внизу независимо от скролла)
  cp5.addButton("saveAndExitBtn").setPosition(20, height - 80).setSize(150, 35).setGroup(eGrp).setCaptionLabel("SAVE TO LIBRARY").setColorBackground(COLOR_SUCCESS);
  cp5.addButton("cancelBtn").setPosition(180, height - 80).setSize(150, 35).setGroup(eGrp).setCaptionLabel("CANCEL (NO SAVE)").setColorBackground(COLOR_DANGER);
}

void createSliderWithInput(Group g, String name, String label, int x, int y, float min, float max, float val) {
  cp5.addSlider(name).setPosition(x, y).setSize(120, 20).setGroup(g).setRange(min, max).setValue(val).setCaptionLabel(label).setColorCaptionLabel(COLOR_WHITE).setColorBackground(color(200)).setColorForeground(COLOR_PRIMARY).setColorActive(COLOR_PRIMARY).getCaptionLabel().align(ControlP5.LEFT, ControlP5.TOP_OUTSIDE).setPaddingX(0);
  cp5.addTextfield("in_" + name).setPosition(x + 130, y).setSize(45, 20).setGroup(g).setCaptionLabel("").setText(str(val)).setAutoClear(false).setColorBackground(COLOR_WHITE).setColorForeground(COLOR_PRIMARY).setColorValueLabel(0);
}

// ==========================================
// LOGIC BUTTONS
// ==========================================
public void libraryList(int n) { if (ignoreUIEvents) return; if (n >= 0 && n < library.size()) selectedLibIndex = n; } 

public void exportBtn() { if (scene.isEmpty()) return; exportSVG(); doExportDXF = true; }

public void exportSVG() { 
  float minX = Float.MAX_VALUE, minY = Float.MAX_VALUE, maxX = -Float.MAX_VALUE, maxY = -Float.MAX_VALUE;
  for (PartInstance p : scene) { minX = min(minX, p.getBoundLeft()); minY = min(minY, p.getBoundTop()); maxX = max(maxX, p.getBoundRight()); maxY = max(maxY, p.getBoundBottom()); }
  float pad = 10, scaleFactor = 96.0f / 25.4f; 
  int svgW = max(10, (int)((maxX - minX + pad*2) * scaleFactor)), svgH = max(10, (int)((maxY - minY + pad*2) * scaleFactor));
  PGraphics svg = createGraphics(svgW, svgH, SVG, "laser_cut_project.svg");
  svg.beginDraw(); svg.pushMatrix(); svg.scale(scaleFactor); svg.translate(-minX + pad, -minY + pad); 
  for (PartInstance inst : scene) inst.display(svg, true, false, false);
  svg.popMatrix(); svg.dispose(); svg.endDraw();
  println("Export finished: laser_cut_project.svg");
}

public void spawnPartBtn() { 
  if (library.size() > 0 && selectedLibIndex >= 0 && selectedLibIndex < library.size()) {
    saveState(); scene.add(new PartInstance(library.get(selectedLibIndex), (width/2-panX)/currentZoom, (height/2-panY)/currentZoom)); 
  }
}

public void openEditorBtn() { 
  mainPanX=panX; mainPanY=panY; mainZoom=currentZoom; panX=width/2; panY=height/2; currentZoom=5.0; appState=STATE_EDITOR; editingIndex = -1;
  editingPart=new PartTemplate("New Part", 100, 100); 
  selectedCutout=null; selectedLine=null; selectedText=null; selectedSVG=null; clearPropertiesUI();
  cp5.get(Textfield.class, "partName").setText(editingPart.name);
  cp5.getGroup("mainGroup").hide(); cp5.getGroup("editorGroup").show(); if (accordion != null) accordion.show(); syncShapeUI(); updateUILabels();
}

public void editPartBtn() {
  if (library.size() > 0 && selectedLibIndex >= 0 && selectedLibIndex < library.size()) {
    mainPanX=panX; mainPanY=panY; mainZoom=currentZoom; panX=width/2; panY=height/2; currentZoom=5.0; 
    appState=STATE_EDITOR; editingIndex = selectedLibIndex; PartTemplate src = library.get(selectedLibIndex);
    editingPart = new PartTemplate(src.name, src.w, src.h);
    editingPart.shapeType = src.shapeType; editingPart.triA = src.triA; editingPart.triB = src.triB; editingPart.triC = src.triC; editingPart.polySides = src.polySides;
    for(int i=0; i<4; i++) editingPart.edges[i] = src.edges[i];
    for(SlotLine sl : src.slotLines) editingPart.slotLines.add(new SlotLine(sl.dir, sl.pos));
    for(Cutout c : src.cutouts) editingPart.cutouts.add(new Cutout(c.type, c.x, c.y, c.w, c.h));
    for(EngraveText et : src.texts) editingPart.texts.add(new EngraveText(et.text, et.x, et.y, et.size));
    for(EngraveSVG es : src.svgs) editingPart.svgs.add(new EngraveSVG(es.filepath, es.x, es.y, es.w, es.h));
    
    selectedCutout=null; selectedLine=null; selectedText=null; selectedSVG=null; clearPropertiesUI();
    cp5.get(Textfield.class, "partName").setText(editingPart.name);
    cp5.getGroup("mainGroup").hide(); cp5.getGroup("editorGroup").show(); if (accordion != null) accordion.show(); syncShapeUI(); updateUILabels();
  }
}

public void deletePartBtn() {
  if (library.size() > 0 && selectedLibIndex >= 0 && selectedLibIndex < library.size()) {
    saveState(); library.remove(selectedLibIndex); savePartLibrary(); 
    selectedLibIndex = (library.size() > 0) ? max(0, min(selectedLibIndex, library.size() - 1)) : 0;
    ignoreUIEvents = true; updateLibraryList(); ignoreUIEvents = false;
  }
}

public void saveAndExitBtn() { 
  edPanX=panX; edPanY=panY; edZoom=currentZoom; panX=mainPanX; currentZoom=mainZoom; appState=STATE_MAIN; 
  saveState(); editingPart.name=cp5.get(Textfield.class, "partName").getText();
  if (editingIndex >= 0) library.set(editingIndex, editingPart); else library.add(editingPart);
  savePartLibrary(); ignoreUIEvents = true; updateLibraryList(); ignoreUIEvents = false;
  editingPart=null; cp5.getGroup("editorGroup").hide(); if (accordion != null) accordion.hide(); cp5.getGroup("mainGroup").show();
}

public void cancelBtn() { 
  edPanX=panX; edPanY=panY; edZoom=currentZoom; panX=mainPanX; panY=mainPanY; currentZoom=mainZoom; appState=STATE_MAIN; editingPart=null; 
  cp5.getGroup("editorGroup").hide(); if (accordion != null) accordion.hide(); cp5.getGroup("mainGroup").show();
}

public void shapeRect() { if(editingPart!=null) { editingPart.shapeType = 0; updateShapeColors("shapeRect"); syncShapeUI(); updateUILabels(); } }
public void shapeCirc() { if(editingPart!=null) { editingPart.shapeType = 1; updateShapeColors("shapeCirc"); syncShapeUI(); updateUILabels(); } }
public void shapeTri()  { if(editingPart!=null) { editingPart.shapeType = 2; updateShapeColors("shapeTri");  syncShapeUI(); updateUILabels(); } }
public void shapePoly() { if(editingPart!=null) { editingPart.shapeType = 3; updateShapeColors("shapePoly"); syncShapeUI(); updateUILabels(); } }

void updateShapeColors(String active) {
  String[] btns = {"shapeRect", "shapeCirc", "shapeTri", "shapePoly"};
  for(String b : btns) cp5.getController(b).setColorBackground(b.equals(active) ? COLOR_PRIMARY : COLOR_INACTIVE);
}

void syncShapeUI() {
  boolean isR = (editingPart.shapeType == 0), isT = (editingPart.shapeType == 2), isP = (editingPart.shapeType == 3);
  cp5.getController("editWidth").setVisible(!isT); cp5.getController("in_editWidth").setVisible(!isT);
  cp5.getController("editHeight").setVisible(isR); cp5.getController("in_editHeight").setVisible(isR);
  cp5.getController("triSideA").setVisible(isT); cp5.getController("in_triSideA").setVisible(isT);
  cp5.getController("triSideB").setVisible(isT); cp5.getController("in_triSideB").setVisible(isT);
  cp5.getController("triSideC").setVisible(isT); cp5.getController("in_triSideC").setVisible(isT);
  if(isT) syncTriSliders();
  cp5.getController("polySides").setVisible(isP); cp5.getController("in_polySides").setVisible(isP);
  updateEditorButtons();
}

public void addHSlotBtn()  { if (editingPart != null) editingPart.slotLines.add(new SlotLine(0, editingPart.h/2)); }
public void addVSlotBtn()  { if (editingPart != null) editingPart.slotLines.add(new SlotLine(1, editingPart.w/2)); }
public void addCSlotBtn()  { if (editingPart != null) editingPart.slotLines.add(new SlotLine(2, min(editingPart.w, editingPart.h)/4)); }
public void addLDSlotBtn() { if (editingPart != null) editingPart.slotLines.add(new SlotLine(3, editingPart.w/4)); }
public void addRDSlotBtn() { if (editingPart != null) editingPart.slotLines.add(new SlotLine(4, editingPart.w/4)); }
public void addRectCutout() { if (editingPart != null) editingPart.cutouts.add(new Cutout(0, editingPart.w/2, editingPart.h/2, 20, 20)); }
public void addCircCutout() { if (editingPart != null) editingPart.cutouts.add(new Cutout(1, editingPart.w/2, editingPart.h/2, 20, 20)); }
public void addTextEngraveBtn() { if (editingPart != null) { String defaultText = cp5.get(Textfield.class, "engraveTextInput").getText(); editingPart.texts.add(new EngraveText(defaultText, editingPart.w/2, editingPart.h/2, 24)); } }
public void addSvgEngraveBtn() { selectInput("Select an SVG file for engraving", "svgSelectedCallback"); }
void svgSelectedCallback(File selection) { if (selection == null || editingPart == null) return; String path = selection.getAbsolutePath(); EngraveSVG es = new EngraveSVG(path, editingPart.w/2, editingPart.h/2, 50, 50); if (es.shape != null) editingPart.svgs.add(es); }

void updateLibraryList() { 
  ScrollableList sl = cp5.get(ScrollableList.class, "libraryList"); sl.clear(); 
  for(int i=0;i<library.size();i++) sl.addItem(library.get(i).name, i);
  if (library.size() > 0 && selectedLibIndex >= 0 && selectedLibIndex < library.size()) sl.setCaptionLabel(library.get(selectedLibIndex).name);
  else sl.setCaptionLabel(t("PART LIBRARY"));
}

public void toggleTop()    { if(editingPart!=null && editingPart.shapeType!=2){editingPart.edges[0]=(editingPart.edges[0]+1)%3; updateEditorButtons();} } 
public void toggleRight()  { if(editingPart!=null && editingPart.shapeType!=1 && editingPart.shapeType!=3){editingPart.edges[1]=(editingPart.edges[1]+1)%3; updateEditorButtons();} } 
public void toggleBottom() { if(editingPart!=null && editingPart.shapeType!=1 && editingPart.shapeType!=3){editingPart.edges[2]=(editingPart.edges[2]+1)%3; updateEditorButtons();} } 
public void toggleLeft()   { if(editingPart!=null && editingPart.shapeType!=1 && editingPart.shapeType!=3){editingPart.edges[3]=(editingPart.edges[3]+1)%3; updateEditorButtons();} }

void updateEditorButtons() { 
  if (editingPart == null || cp5.getController("toggleTop") == null) return;
  String[] s={t("FLAT"), t("TABS"), t("SLOTS")}; cp5.getController("addHSlotBtn").show();
  if (editingPart.shapeType == 0) {
    cp5.getController("toggleTop").setCaptionLabel(t("TOP") + ": "+s[editingPart.edges[0]]);
    cp5.getController("toggleRight").setCaptionLabel(t("RIGHT") + ": "+s[editingPart.edges[1]]); 
    cp5.getController("toggleBottom").setCaptionLabel(t("BOTTOM") + ": "+s[editingPart.edges[2]]);
    cp5.getController("toggleLeft").setCaptionLabel(t("LEFT") + ": "+s[editingPart.edges[3]]);
    cp5.getController("addVSlotBtn").show(); cp5.getController("addCSlotBtn").hide(); cp5.getController("addLDSlotBtn").hide(); cp5.getController("addRDSlotBtn").hide();
  } else if (editingPart.shapeType == 1 || editingPart.shapeType == 3) {
    cp5.getController("toggleTop").setCaptionLabel(t("ALL EDGES") + ": "+s[editingPart.edges[0]]);
    cp5.getController("toggleRight").setCaptionLabel("---"); cp5.getController("toggleBottom").setCaptionLabel("---"); cp5.getController("toggleLeft").setCaptionLabel("---");
    cp5.getController("addVSlotBtn").show();
    if(editingPart.shapeType == 1 || editingPart.shapeType == 3) { cp5.getController("addCSlotBtn").show(); cp5.getController("addCSlotBtn").setCaptionLabel(t(editingPart.shapeType == 3 ? "ADD P-SLOT" : "ADD C-SLOT")); } 
    else { cp5.getController("addCSlotBtn").hide(); }
    cp5.getController("addLDSlotBtn").hide(); cp5.getController("addRDSlotBtn").hide();
  } else if (editingPart.shapeType == 2) {
    cp5.getController("toggleTop").setCaptionLabel("---");
    cp5.getController("toggleRight").setCaptionLabel(t("RIGHT DIAG") + ": "+s[editingPart.edges[1]]);
    cp5.getController("toggleBottom").setCaptionLabel(t("BOTTOM") + ": "+s[editingPart.edges[2]]); cp5.getController("toggleLeft").setCaptionLabel(t("LEFT DIAG") + ": "+s[editingPart.edges[3]]);
    cp5.getController("addVSlotBtn").hide(); cp5.getController("addCSlotBtn").hide(); cp5.getController("addLDSlotBtn").show(); cp5.getController("addRDSlotBtn").show();
  }
}

// ==========================================
// JSON AUTO-SAVE & AUTO-LOAD (Без изменений)
// ==========================================
public void savePartLibrary() { 
  JSONArray ja = new JSONArray();
  for(int i=0; i<library.size(); i++) { 
    PartTemplate t = library.get(i); JSONObject jo = new JSONObject();
    jo.setString("name",t.name); jo.setInt("shape", t.shapeType); jo.setFloat("w",t.w); jo.setFloat("h",t.h); 
    jo.setFloat("triA", t.triA); jo.setFloat("triB", t.triB); jo.setFloat("triC", t.triC); jo.setInt("polySides", t.polySides);
    JSONArray ea=new JSONArray(); for(int j=0;j<4;j++) ea.setInt(j,t.edges[j]); jo.setJSONArray("edges",ea);
    JSONArray sla=new JSONArray(); for (int k=0; k<t.slotLines.size(); k++) { JSONObject slo = new JSONObject(); slo.setInt("dir",t.slotLines.get(k).dir); slo.setFloat("pos",t.slotLines.get(k).pos); sla.append(slo); } jo.setJSONArray("slotLines", sla);
    JSONArray cutA=new JSONArray(); for (int k=0; k<t.cutouts.size(); k++) { JSONObject c = new JSONObject(); c.setInt("type",t.cutouts.get(k).type); c.setFloat("x",t.cutouts.get(k).x); c.setFloat("y",t.cutouts.get(k).y); c.setFloat("w",t.cutouts.get(k).w); c.setFloat("h",t.cutouts.get(k).h); cutA.append(c); } jo.setJSONArray("cutouts", cutA); 
    JSONArray txtA = new JSONArray(); for(EngraveText et : t.texts) { JSONObject txtObj = new JSONObject(); txtObj.setFloat("x", et.x); txtObj.setFloat("y", et.y); txtObj.setString("t", et.text); txtObj.setFloat("s", et.size); txtA.append(txtObj); } jo.setJSONArray("texts", txtA);
    JSONArray svgA = new JSONArray(); for(EngraveSVG es : t.svgs) { JSONObject so = new JSONObject(); so.setFloat("x", es.x); so.setFloat("y", es.y); so.setFloat("w", es.w); so.setFloat("h", es.h); so.setString("p", es.filepath); svgA.append(so); } jo.setJSONArray("svgs", svgA);
    ja.setJSONObject(i,jo); 
  } saveJSONArray(ja,"data/library.json");
}

public void loadPartLibrary() { 
  try { JSONArray ja = loadJSONArray("data/library.json"); library.clear();
    for(int i=0;i<ja.size();i++) { 
      JSONObject jo=ja.getJSONObject(i); PartTemplate t=new PartTemplate(jo.getString("name"),jo.getFloat("w"),jo.getFloat("h"));
      if(!jo.isNull("shape")) t.shapeType = jo.getInt("shape");
      if(!jo.isNull("triA")) { t.triA=jo.getFloat("triA"); t.triB=jo.getFloat("triB"); t.triC=jo.getFloat("triC"); }
      if(!jo.isNull("polySides")) t.polySides = jo.getInt("polySides");
      if(t.shapeType == 2) t.validateTriangle(); if(t.shapeType == 3) t.validatePolygon();
      JSONArray ea=jo.getJSONArray("edges"); for(int j=0;j<4;j++) t.edges[j]=ea.getInt(j); 
      if (!jo.isNull("slotLines")) { JSONArray sla = jo.getJSONArray("slotLines"); for (int k=0; k<sla.size(); k++) { JSONObject slo = sla.getJSONObject(k); t.slotLines.add(new SlotLine(slo.getInt("dir"),slo.getFloat("pos"))); } } 
      if (!jo.isNull("cutouts")) { JSONArray cutA = jo.getJSONArray("cutouts"); for (int k=0; k<cutA.size(); k++) { JSONObject c = cutA.getJSONObject(k); t.cutouts.add(new Cutout(c.getInt("type"),c.getFloat("x"),c.getFloat("y"),c.getFloat("w"),c.getFloat("h"))); } } 
      if (!jo.isNull("texts")) { JSONArray txtA = jo.getJSONArray("texts"); for (int k=0; k<txtA.size(); k++) { JSONObject txtObj = txtA.getJSONObject(k); t.texts.add(new EngraveText(txtObj.getString("t"), txtObj.getFloat("x"), txtObj.getFloat("y"), txtObj.getFloat("s"))); } }
      if (!jo.isNull("svgs")) { JSONArray svgA = jo.getJSONArray("svgs"); for (int k=0; k<svgA.size(); k++) { JSONObject so = svgA.getJSONObject(k); t.svgs.add(new EngraveSVG(so.getString("p"), so.getFloat("x"), so.getFloat("y"), so.getFloat("w"), so.getFloat("h"))); } }
      library.add(t);
    } updateLibraryList();
  } catch(Exception e) {} 
}

// ==========================================
// GEOMETRY CLASSES (Минимальные изменения для Hover)
// ==========================================
class EngraveText { float x, y, size; String text; EngraveText(String t, float x, float y, float s) { this.text = t; this.x = x; this.y = y; this.size = s; } }
class EngraveSVG {
    float x, y, w, h; String filepath; PShape shape; float origW = 50, origH = 50, aspect = 1.0; float vbW = -1, vbH = -1;
    EngraveSVG(String path, float x, float y, float w, float h) {
        this.filepath = path; this.x = x; this.y = y; this.w = w; this.h = h;
        try { shape = loadShape(path);
            if (shape != null) { origW = shape.width > 0 ? shape.width : 50; origH = shape.height > 0 ? shape.height : 50;
                try { XML xml = loadXML(path); if (xml != null) { String vbStr = xml.getString("viewBox"); if (vbStr != null) { String[] vb = vbStr.trim().split("[\\s,]+"); if (vb.length >= 4) { vbW = Float.parseFloat(vb[2]); vbH = Float.parseFloat(vb[3]); } } } } catch (Exception e) {}
                if (vbW == -1) { vbW = origW; vbH = origH; }
                aspect = origW / origH; if (this.w == 50 && this.h == 50) { float fitScale = min(50.0f / origW, 50.0f / origH); this.w = origW * fitScale; this.h = origH * fitScale; } else { aspect = this.w / this.h; }
            }
        } catch (Exception e) { println("Failed to load SVG: " + path); }
    }
}

class Cutout {
  int type; float x, y, w, h; Cutout(int type, float x, float y, float w, float h) { this.type = type; this.x = x; this.y = y; this.w = w; this.h = h; }
  void draw(PGraphics pg, boolean exporting, boolean isSelected) {
    pg.pushMatrix(); if (!exporting) pg.translate(0, 0, 0.05f); 
    pg.pushStyle();
    if (!exporting) { pg.fill(255); if (isSelected) { pg.stroke(46, 204, 113); pg.strokeWeight(2.0f/currentZoom); } else { pg.noStroke(); } } 
    else { pg.noFill(); pg.stroke(255, 0, 0); pg.strokeWeight(0.01f); }
    float realW = w - kerf, realH = h - kerf; pg.beginShape();
    if (type == 0) { pg.vertex(x - realW/2, y - realH/2); pg.vertex(x + realW/2, y - realH/2); pg.vertex(x + realW/2, y + realH/2); pg.vertex(x - realW/2, y + realH/2); } 
    else if (type == 1) { int steps = max(36, floor(PI * realW)); for (int i=0; i<steps; i++) { float a = TWO_PI * i / steps; pg.vertex(x + (realW/2)*cos(a), y + (realH/2)*sin(a)); } }
    pg.endShape(CLOSE); pg.popStyle(); pg.popMatrix();
  }
}

class SlotLine {
  int dir; float pos; float lx1, ly1, lx2, ly2; float startDragPos; int lastRenderedTabs = 0; float lastRenderedTW = 0;
  SlotLine(int dir, float pos) { this.dir = dir; this.pos = pos; }
  void drawSlots(PGraphics pg, PartTemplate t, boolean exporting) {
    float cx = t.w/2.0f, cy = t.h/2.0f; float r = min(t.w, t.h)/2.0f;
    if (dir == 2) { 
        if (t.shapeType == 1) { 
            if (pos > 0 && pos <= r) {
                float TW = tabWidth; int k = max(3, floor((TWO_PI * pos) / (TW * 2.0f))); float aTab = TW / pos; float aGap = (TWO_PI - k * aTab) / k;
                if (!exporting) { pg.pushMatrix(); pg.translate(0, 0, 0.05f); pg.pushStyle(); pg.noFill(); pg.ellipseMode(CENTER); if (this == selectedLine) { pg.stroke(46, 204, 113); pg.strokeWeight(2.0f/currentZoom); } else { pg.stroke(255, 255, 255, 120); pg.strokeWeight(1.0f/currentZoom); } pg.ellipse(cx, cy, pos*2, pos*2); pg.popStyle(); pg.popMatrix(); }
                if (exporting) { pg.noFill(); pg.stroke(255, 0, 0); pg.strokeWeight(0.01f); } else { pg.fill(240); pg.stroke(44, 62, 80); pg.strokeWeight(1.0f/currentZoom); }
                for (int i = 0; i < k; i++) { float aStart = i * (aTab + aGap) + aGap/2.0f; pg.pushMatrix(); pg.translate(cx + pos*cos(aStart + aTab/2.0f), cy + pos*sin(aStart + aTab/2.0f)); if (!exporting) pg.translate(0, 0, 0.05f); pg.rotate(aStart + aTab/2.0f + HALF_PI); pg.rect(-TW/2.0f + kerf/2.0f, -tabDepth/2.0f + kerf/2.0f, TW - kerf, tabDepth - kerf); pg.popMatrix(); }
            } return;
        } else if (t.shapeType == 3) { 
            if (pos > 0 && pos <= r) {
                float aStep = TWO_PI / t.polySides; float[][] innerPts = new float[t.polySides][2];
                for (int i = 0; i < t.polySides; i++) { float a = i * aStep - HALF_PI; innerPts[i][0] = cx + pos * cos(a); innerPts[i][1] = cy + pos * sin(a); }
                for (int e = 0; e < t.polySides; e++) {
                    float[] p1 = innerPts[e], p2 = innerPts[(e + 1) % t.polySides]; float ex = p2[0] - p1[0], ey = p2[1] - p1[1]; float el = dist(p1[0], p1[1], p2[0], p2[1]);
                    if (el == 0) continue; ex /= el; ey /= el; float angle = atan2(ey, ex); float TW = tabWidth; if (el < TW) TW = el * 0.8f; int k = max(1, floor(el / (TW * 2.0f))); float gapSize = (el - k * TW) / (k + 1.0f);
                    if (!exporting) { pg.pushMatrix(); pg.translate(0, 0, 0.05f); pg.pushStyle(); if (this == selectedLine) { pg.stroke(46, 204, 113); pg.strokeWeight(2.0f/currentZoom); } else { pg.stroke(255, 255, 255, 120); pg.strokeWeight(1.0f/currentZoom); } pg.line(p1[0], p1[1], p2[0], p2[1]); pg.popStyle(); pg.popMatrix(); }
                    if (exporting) { pg.noFill(); pg.stroke(255, 0, 0); pg.strokeWeight(0.01f); } else { pg.fill(240); pg.stroke(44, 62, 80); pg.strokeWeight(1.0f/currentZoom); }
                    float currentPos = gapSize; for (int i = 0; i < k; i++) { pg.pushMatrix(); pg.translate(p1[0] + ex*currentPos, p1[1] + ey*currentPos); if (!exporting) pg.translate(0, 0, 0.05f); pg.rotate(angle); pg.rect(kerf/2.0f, -tabDepth/2.0f + kerf/2.0f, TW - kerf, tabDepth - kerf); pg.popMatrix(); currentPos += TW + gapSize; }
                }
            } return;
        }
    }
    float px=0, py=0, dx=1, dy=0;
    if (dir == 0) { px = 0; py = pos; dx = 1; dy = 0; } 
    else if (dir == 1) { px = pos; py = 0; dx = 0; dy = 1; } 
    else if ((dir == 3 || dir == 4) && t.shapeType == 2) {
        float[][] pts = t.getVertices(); float[] pStart, pEnd, pThird;
        if (dir == 3) { pStart = pts[0]; pEnd = pts[2]; pThird = pts[1]; } else { pStart = pts[1]; pEnd = pts[2]; pThird = pts[0]; } 
        float ex = pEnd[0] - pStart[0], ey = pEnd[1] - pStart[1]; float el = sqrt(ex*ex + ey*ey); ex/=el; ey/=el;
        float nx1 = -ey, ny1 = ex, nx2 = ey, ny2 = -ex; float tx = pThird[0] - pStart[0], ty = pThird[1] - pStart[1];
        if (tx*nx1 + ty*ny1 > 0) { px = pStart[0] + nx1*pos; py = pStart[1] + ny1*pos; } else { px = pStart[0] + nx2*pos; py = pStart[1] + ny2*pos; } dx = ex; dy = ey;
    }
    float len = 0, startX = 0, startY = 0;
    if (t.shapeType == 1) { 
        if (dir == 0) { float dyC = abs(pos - cy); if (dyC < r) { float dxC = sqrt(r*r - dyC*dyC); startX = cx - dxC; startY = pos; len = 2*dxC; } }
        else if (dir == 1) { float dxC = abs(pos - cx); if (dxC < r) { float dyC = sqrt(r*r - dxC*dxC); startX = pos; startY = cy - dyC; len = 2*dyC; } }
    } else { 
        float[][] pts = t.getVertices(); ArrayList<float[]> ints = new ArrayList<float[]>(); float nx = -dy, ny = dx;
        for (int i=0; i<pts.length; i++) {
            float[] p1 = pts[i], p2 = pts[(i+1)%pts.length]; float d1 = (p1[0]-px)*nx + (p1[1]-py)*ny, d2 = (p2[0]-px)*nx + (p2[1]-py)*ny;
            if ((d1 >= 0 && d2 <= 0) || (d1 <= 0 && d2 >= 0)) { if (d1 - d2 != 0) { float frac = d1 / (d1 - d2); ints.add(new float[]{p1[0] + frac*(p2[0]-p1[0]), p1[1] + frac*(p2[1]-p1[1])}); } }
        }
        if (ints.size() >= 2) {
            float[] i1 = ints.get(0), i2 = ints.get(1); for(float[] p : ints) if (dist(i1[0], i1[1], p[0], p[1]) > dist(i1[0], i1[1], i2[0], i2[1])) i2 = p;
            startX = i1[0]; startY = i1[1]; float endX = i2[0], endY = i2[1];
            if ((endX-startX)*dx + (endY-startY)*dy < 0) { startX = endX; startY = endY; endX = i1[0]; endY = i1[1]; } len = dist(startX, startY, endX, endY);
        }
    }
    if (len > 0) {
        float TW = tabWidth; if (len < TW) TW = len * 0.8f; int k = max(1, floor(len / (TW * 2.0f))); float gapSize = (len - k * TW) / (k + 1.0f);
        lastRenderedTW = TW; lastRenderedTabs = k; lx1 = startX; ly1 = startY; lx2 = startX + dx*len; ly2 = startY + dy*len;
        if (!exporting) { pg.pushMatrix(); pg.translate(0, 0, 0.05f); pg.pushStyle(); if (this == selectedLine) { pg.stroke(46, 204, 113); pg.strokeWeight(2.0f/currentZoom); } else { pg.stroke(255, 255, 255, 120); pg.strokeWeight(1.0f/currentZoom); } pg.line(lx1, ly1, lx2, ly2); pg.popStyle(); pg.popMatrix(); }
        if (exporting) { pg.noFill(); pg.stroke(255, 0, 0); pg.strokeWeight(0.01f); } else { pg.fill(240); pg.stroke(44, 62, 80); pg.strokeWeight(1.0f/currentZoom); }
        float angle = atan2(dy, dx); float currentPos = gapSize;
        for (int i = 0; i < k; i++) { pg.pushMatrix(); pg.translate(startX + dx*currentPos, startY + dy*currentPos); if (!exporting) pg.translate(0, 0, 0.05f); pg.rotate(angle); pg.rect(kerf/2.0f, -tabDepth/2.0f + kerf/2.0f, TW - kerf, tabDepth - kerf); pg.popMatrix(); currentPos += TW + gapSize; }
    } else { lx1=0; ly1=0; lx2=0; ly2=0; lastRenderedTabs = 0;} 
  }
}

class PartTemplate {
  String name; int shapeType = 0; float w = 100, h = 100; float triA = 100, triB = 100, triC = 100; int polySides = 5;
  int[] edges = {0, 0, 0, 0}; ArrayList<SlotLine> slotLines = new ArrayList<SlotLine>(); ArrayList<Cutout> cutouts = new ArrayList<Cutout>();
  ArrayList<EngraveText> texts = new ArrayList<EngraveText>(); ArrayList<EngraveSVG> svgs = new ArrayList<EngraveSVG>();
  PartTemplate(String name, float w, float h) { this.name = name; this.w = w; this.h = h; }
  
  float getEstimatePerimeter() {
     float p = 0;
     if (shapeType == 1) { float R = min(w, h)/2.0f; p += TWO_PI * R; if (edges[0] != 0) p += max(3, floor((TWO_PI * R) / (tabWidth * 2.0f))) * 2 * tabDepth; } 
     else if (shapeType == 3) { float[][] v = getVertices(); for(int i=0; i<polySides; i++) { float d = dist(v[i][0], v[i][1], v[(i+1)%polySides][0], v[(i+1)%polySides][1]); p += d; if (edges[0] != 0) { float TW = tabWidth; if(d<TW) TW=d*0.8f; p += max(1, floor(d / (TW * 2.0f))) * 2 * tabDepth; } } } 
     else if (shapeType == 0) { p += calcEdgeEst(w, edges[0]) + calcEdgeEst(h, edges[1]) + calcEdgeEst(w, edges[2]) + calcEdgeEst(h, edges[3]); } 
     else if (shapeType == 2) { p += calcEdgeEst(triB, edges[1]) + calcEdgeEst(triA, edges[2]) + calcEdgeEst(triC, edges[3]); }
     for (Cutout c : cutouts) p += (c.type==0) ? (c.w*2 + c.h*2) : (PI*c.w);
     for (SlotLine sl : slotLines) {
         if (sl.dir == 2 && shapeType == 1) { float R = sl.pos; float TW = tabWidth; int k = max(3, floor((TWO_PI * R) / (TW * 2.0f))); p += k * (TW*2 + tabDepth*2); } 
         else if (sl.dir == 2 && shapeType == 3) { float TW = tabWidth; float sideLen = 2 * sl.pos * sin(PI / polySides); if (sideLen < TW) TW = sideLen * 0.8f; int k = max(1, floor(sideLen / (TW * 2.0f))); p += polySides * k * (TW * 2 + tabDepth * 2); } 
         else { p += sl.lastRenderedTabs * (sl.lastRenderedTW*2 + tabDepth*2); }
     } return p;
  }
  
  float calcEdgeEst(float len, int type) { if (type == 0) return len; float TW = tabWidth; if (len<TW) TW=len*0.8f; return len + max(1, floor(len / (TW * 2.0f))) * 2 * tabDepth; }

  void validateTriangle() {
     if (triA + triB <= triC + 0.1) triC = max(1, triA + triB - 1); if (triA + triC <= triB + 0.1) triB = max(1, triA + triC - 1); if (triB + triC <= triA + 0.1) triA = max(1, triB + triC - 1);
     float xc = (triA*triA + triC*triC - triB*triB) / (2*triA); this.w = max(triA, xc) + max(0, -xc); this.h = sqrt(max(0, triC*triC - xc*xc));
  }
  void validatePolygon() { this.h = this.w; }

  float[][] getVertices() {
    if (shapeType == 0) return new float[][]{ {0,0}, {w,0}, {w,h}, {0,h} };
    else if (shapeType == 2) { float xc = (triA*triA + triC*triC - triB*triB) / (2*triA); float yc = sqrt(max(0, triC*triC - xc*xc)); float xOff = max(0, -xc); return new float[][]{ {xOff, yc}, {triA + xOff, yc}, {xc + xOff, 0} }; } 
    else if (shapeType == 3) { float R = w / 2.0f; float[][] pts = new float[polySides][2]; float aStep = TWO_PI / polySides; for (int i = 0; i < polySides; i++) { float a = i * aStep - HALF_PI; pts[i][0] = R + R * cos(a); pts[i][1] = R + R * sin(a); } return pts; }
    return new float[][]{};
  }

  // === NEW: Передаем флаг isHovered ===
  void drawShape(PGraphics pg, boolean exporting, boolean isSelected, boolean isHovered) {
    if (!exporting) { 
        pg.fill(41, 128, 185, 180);
        if (isSelected) { pg.stroke(231, 76, 60); pg.strokeWeight(2.0f/currentZoom); } 
        else if (isHovered) { pg.stroke(COLOR_PRIMARY); pg.strokeWeight(2.5f/currentZoom); } // Эффект Hover
        else { pg.stroke(44, 62, 80); pg.strokeWeight(1.0f/currentZoom); } 
    } else { pg.noFill(); pg.stroke(255, 0, 0); pg.strokeWeight(0.01f); }
    
    pg.beginShape();
    if (shapeType == 1) { 
      float cx = w / 2.0f, cy = h / 2.0f, R = min(w, h) / 2.0f;
      if (edges[0] == 0) { float rArc = R + kerf / 2.0f; int steps = max(36, floor(TWO_PI * rArc)); for (int i=0; i<steps; i++) pg.vertex(cx + rArc * cos(TWO_PI*i/steps), cy + rArc * sin(TWO_PI*i/steps)); } 
      else { 
        float TW = tabWidth; int numTabs = max(3, floor((TWO_PI * R) / (TW * 2.0f))); float aTab = TW / R; float aGap = (TWO_PI - numTabs * aTab) / numTabs; float k = kerf / 2.0f; float aOffset = k / R;
        for (int i = 0; i < numTabs; i++) {
          float a0 = i * (aTab + aGap), a1 = a0 + aGap, a2 = a1 + aTab; float rGap = R, rTab = R;
          if (edges[0] == 1) { rTab = R + tabDepth + k; rGap = R - k; } else if (edges[0] == 2) { rTab = R - tabDepth - k; rGap = R + k; }
          float gStart = a0, gEnd = a1; if (edges[0] == 1) { gStart += aOffset; gEnd -= aOffset; } else { gStart -= aOffset; gEnd += aOffset; }
          int arcStepsG = max(2, ceil(abs(gEnd - gStart) / 0.05f)); for (int j = 0; j <= arcStepsG; j++) pg.vertex(cx + rGap * cos(gStart + (gEnd - gStart) * j / arcStepsG), cy + rGap * sin(gStart + (gEnd - gStart) * j / arcStepsG));
          float tStart = a1, tEnd = a2; if (edges[0] == 1) { tStart -= aOffset; tEnd += aOffset; } else { tStart += aOffset; tEnd -= aOffset; }
          int arcStepsT = max(2, ceil(abs(tEnd - tStart) / 0.05f)); for (int j = 0; j <= arcStepsT; j++) pg.vertex(cx + rTab * cos(tStart + (tEnd - tStart) * j / arcStepsT), cy + rTab * sin(tStart + (tEnd - tStart) * j / arcStepsT));
        }
      }
    } else if (shapeType == 2) { 
      float[][] v = getVertices(); addEdgeGen(pg, triB, edges[1], v[2][0], v[2][1], atan2(v[1][1]-v[2][1], v[1][0]-v[2][0])); addEdgeGen(pg, triA, edges[2], v[1][0], v[1][1], atan2(v[0][1]-v[1][1], v[0][0]-v[1][0])); addEdgeGen(pg, triC, edges[3], v[0][0], v[0][1], atan2(v[2][1]-v[0][1], v[2][0]-v[0][0])); 
    } else if (shapeType == 3) {
      float[][] v = getVertices(); for (int i = 0; i < polySides; i++) { float[] p1 = v[i], p2 = v[(i+1)%polySides]; addEdgeGen(pg, dist(p1[0],p1[1],p2[0],p2[1]), edges[0], p1[0], p1[1], atan2(p2[1]-p1[1], p2[0]-p1[0])); }
    } else { 
      addEdgeGen(pg, w, edges[0], 0, 0, 0); addEdgeGen(pg, h, edges[1], w, 0, HALF_PI); addEdgeGen(pg, w, edges[2], w, h, PI); addEdgeGen(pg, h, edges[3], 0, h, -HALF_PI);
    }
    pg.endShape(CLOSE);
    for (SlotLine line : slotLines) line.drawSlots(pg, this, exporting);
    for (Cutout c : cutouts) c.draw(pg, exporting, c == selectedCutout);
    
    // Draw Engravings
    pg.pushStyle();
    for (EngraveText et : texts) {
        pg.pushMatrix(); pg.translate(et.x, et.y); if (!exporting) pg.translate(0, 0, 0.06f);
        if (exporting) { pg.fill(0, 0, 255); pg.noStroke(); } else { pg.fill(et == selectedText ? COLOR_SUCCESS : COLOR_ENGRAVE); }
        pg.textAlign(CENTER, CENTER); pg.textSize(et.size); pg.text(et.text, 0, 0); pg.popMatrix();
    }
    for (EngraveSVG es : svgs) {
        if (es.shape != null) {
            pg.pushMatrix(); pg.translate(es.x, es.y); if (!exporting) pg.translate(0, 0, 0.06f);
            if (!exporting && es == selectedSVG) { pg.noFill(); pg.stroke(COLOR_SUCCESS); pg.strokeWeight(2.0f/currentZoom); pg.rect(-es.w/2, -es.h/2, es.w, es.h); }
            es.shape.disableStyle(); if (exporting) { pg.fill(0, 0, 255); pg.noStroke(); } else { pg.fill(COLOR_ENGRAVE); pg.noStroke(); }
            if (exporting) { pg.scale(es.w / es.vbW, es.h / es.vbH); pg.shape(es.shape, -es.vbW/2, -es.vbH/2); } else { pg.scale(es.w / es.origW, es.h / es.origH); pg.shape(es.shape, -es.origW/2, -es.origH/2); }
            pg.popMatrix();
        }
    }
    pg.popStyle();
  }

  void addEdgeGen(PGraphics pg, float len, int type, float sx, float sy, float angle) {
    float k = kerf / 2.0f; if (type == 0) { emitV(pg, -k, -k, sx, sy, angle); return; }
    float TW = tabWidth; if (len < TW) TW = len * 0.8f; int numTabs = max(1, floor(len / (TW * 2.0f))); float gapSize = (len - numTabs * TW) / (numTabs + 1.0f); emitV(pg, -k, -k, sx, sy, angle);
    float currentX = 0;
    for (int i = 0; i < numTabs; i++) {
      float xA = currentX + gapSize; float xB = xA + TW; float yD = (type == 1) ? -tabDepth : tabDepth; float kx = (type == 1) ? k : -k; float ky = (type == 1) ? -k : k;
      emitV(pg, xA - kx, -k, sx, sy, angle); emitV(pg, xA - kx, yD + ky, sx, sy, angle); emitV(pg, xB + kx, yD + ky, sx, sy, angle); emitV(pg, xB + kx, -k, sx, sy, angle); currentX = xB;
    }
  }
  void emitV(PGraphics pg, float lx, float ly, float sx, float sy, float angle) { pg.vertex(sx + lx * cos(angle) - ly * sin(angle), sy + lx * sin(angle) + ly * cos(angle)); }
}

class PartInstance {
  PartTemplate template; float x, y; int rot = 0; float dragStartX, dragStartY;
  PartInstance(PartTemplate template, float x, float y) { this.template = template; this.x = x; this.y = y; }
  float getRealW() { return (rot % 2 == 0) ? template.w : template.h; }
  float getRealH() { return (rot % 2 == 0) ? template.h : template.w; }
  int getWorldEdge(int dir) { return template.shapeType == 0 ? template.edges[(dir + 4 - rot) % 4] : 0; }
  float getBoundLeft() { return x - (getWorldEdge(3) == 1 ? tabDepth : 0); }
  float getBoundRight() { return x + getRealW() + (getWorldEdge(1) == 1 ? tabDepth : 0); }
  float getBoundTop() { return y - (getWorldEdge(0) == 1 ? tabDepth : 0); }
  float getBoundBottom() { return y + getRealH() + (getWorldEdge(2) == 1 ? tabDepth : 0); }

  void display(PGraphics pg, boolean exporting, boolean isSelected, boolean isHovered) {
    pg.pushMatrix(); pg.translate(x, y);
    if (isSelected && !exporting) pg.translate(0, 0, 0.1f); 
    if (rot == 1) { pg.translate(getRealW(), 0); pg.rotate(HALF_PI); } else if (rot == 2) { pg.translate(getRealW(), getRealH()); pg.rotate(PI); } else if (rot == 3) { pg.translate(0, getRealH()); pg.rotate(PI + HALF_PI); }
    template.drawShape(pg, exporting, isSelected, isHovered); 
    pg.popMatrix();
  }
  boolean contains(float px, float py) { return px >= x && px <= x + getRealW() && py >= y && py <= y + getRealH(); }
}

void drawGrid() {
  pushMatrix(); translate(0, 0, -1.0f); stroke(220); strokeWeight(1.0f/currentZoom);
  float sX = -panX/currentZoom - 500, eX = (width-panX)/currentZoom + 500, sY = -panY/currentZoom - 500, eY = (height-panY)/currentZoom + 500;
  sX -= sX % 10; sY -= sY % 10;
  for (float i = sX; i < eX; i += 10) line(i, sY, i, eY);
  for (float i = sY; i < eY; i += 10) line(sX, i, eX, i);
  stroke(150); strokeWeight(2.0f/currentZoom);
  line(0, -10000, 0, 10000); line(-10000, 0, 10000, 0); popMatrix();
}
