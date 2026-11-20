import { LightningElement, api } from "lwc";

export default class SequenceVisualizer extends LightningElement {
  @api sequence = "";
  @api features = [];
  view = "linear";
  get viewOptions() {
    return [
      { label: "Linear", value: "linear" },
      { label: "Circular", value: "circular" }
    ];
  }
  handleView(event) {
    this.view = event.detail.value;
  }
  get isCircular() {
    return this.view === "circular";
  }
  get length() {
    return this.sequence.length;
  }
  get summary() {
    const gc = (this.sequence.match(/[GC]/gi) || []).length;
    const known = (this.sequence.match(/[ACGT]/gi) || []).length;
    const unknown = (this.sequence.match(/N/gi) || []).length;
    return (
      this.length +
      " bp | GC " +
      (known ? ((100 * gc) / known).toFixed(1) : "0.0") +
      "% | " +
      unknown +
      " unknown bases"
    );
  }
  get mapFeatures() {
    const lanes = [];
    return [...this.features]
      .filter(
        (f) =>
          Number.isInteger(Number(f.start)) &&
          Number.isInteger(Number(f.end)) &&
          f.start >= 1 &&
          f.end >= f.start &&
          f.end <= this.length
      )
      .sort((a, b) => a.start - b.start || a.end - b.end)
      .map((feature, index) => {
        let lane = lanes.findIndex((end) => end < feature.start);
        if (lane < 0) lane = lanes.length;
        lanes[lane] = feature.end;
        const start = Number(feature.start),
          end = Number(feature.end);
        const radius = 105 + (lane % 8) * 8;
        const a = -Math.PI / 2 + (2 * Math.PI * (start - 1)) / this.length;
        const span = (2 * Math.PI * (end - start + 1)) / this.length;
        const point = (angle) =>
          [200 + radius * Math.cos(angle), 200 + radius * Math.sin(angle)].join(
            " "
          );
        const path =
          span >= 2 * Math.PI - 0.00001
            ? "M " +
              point(a) +
              " A " +
              radius +
              " " +
              radius +
              " 0 1 1 " +
              point(a + Math.PI) +
              " A " +
              radius +
              " " +
              radius +
              " 0 1 1 " +
              point(a + span)
            : "M " +
              point(a) +
              " A " +
              radius +
              " " +
              radius +
              " 0 " +
              (span > Math.PI ? 1 : 0) +
              " 1 " +
              point(a + span);
        return {
          ...feature,
          key: String(index),
          path,
          description:
            feature.label +
            ": " +
            start +
            "-" +
            end +
            (String(feature.strand) === "-1" ? " (reverse)" : " (forward)"),
          className:
            feature.source === "plannotate"
              ? "feature automatic"
              : "feature manual",
          style:
            "left:" +
            (100 * (start - 1)) / this.length +
            "%;width:" +
            Math.max(0.2, (100 * (end - start + 1)) / this.length) +
            "%;top:" +
            (lane * 30 + 12) +
            "px;",
          lane
        };
      });
  }
  get mapStyle() {
    return (
      "height:" +
      Math.max(70, ...this.mapFeatures.map((f) => (f.lane + 1) * 30 + 20)) +
      "px;"
    );
  }
  get hasFeatures() {
    return this.mapFeatures.length > 0;
  }
  get sequenceLines() {
    const lines = [];
    for (let start = 0; start < this.length; start += 60)
      lines.push(
        String(start + 1).padStart(6, " ") +
          "  " +
          this.sequence.slice(start, start + 60)
      );
    return lines.join("\n");
  }
}
