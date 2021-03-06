const Role = class {
  constructor(rec) {
    Object.assign(this, rec)
  }

  getName() { return this.name }

  isTitular() { return !!this.titular }

  isDesignated() { return !!this.designated }

  isQualifiable() { return !!this.qualifiable }
}

export { Role }
