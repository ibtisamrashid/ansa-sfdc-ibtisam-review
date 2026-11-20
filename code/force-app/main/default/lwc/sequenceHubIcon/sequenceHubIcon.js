import { LightningElement, api } from "lwc";
export default class SequenceHubIcon extends LightningElement {
  @api name;
  get isOptimize() {
    return this.name === "optimize";
  }
  get isAdd() {
    return this.name === "add";
  }
  get isFeasibility() {
    return this.name === "feasibility";
  }
  get isShare() {
    return this.name === "share";
  }
}
