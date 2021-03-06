import * as fs from 'fs'

const Node = class {
  constructor([name, primMngrName, possibleMngrNames], implied = false) {
    this.name = name
    this.implied = implied
    this.primMngrName = primMngrName
    this.primMngr = undefined
    this.possibleMngrNames = possibleMngrNames || []
    if (primMngrName) this.possibleMngrNames.unshift(primMngrName)
    this.possibleMngrs = []
    this.children = []
  }

  getName() { return this.name }

  getPrimMngr() { return this.primMngr }

  getPossibleMngrs() { return this.possibleMngrs }

  getChildren() { return this.children }

  getDescendents() {
    return this.children.reduce((desc, child) => desc.concat(child.getDescendents()), [...this.children])
  }

  getTreeNodes() {
    return this.children.reduce((desc, child) => desc.concat(child.getTreeNodes()), [this])
  }
}

const OrgStructure = class {
  constructor(fileName, roles) {
    const nodes = JSON.parse(fs.readFileSync(fileName)).map(r => new Node(r))
    this.roots = []

    const processNode = (node) => {
      if (node.primMngrName === null) {
        node.primMngr = null // which is not undefined, but positively null
        this.roots.push(node)
      }
      else {
        const primMngr = nodes.find(n => n.name === node.primMngrName)
        if (primMngr === undefined) {
          throw new Error(`Invalid org structure. Role '${node.name}' references `
                          + `non-existent primary manager role '${node.primMngrName}'.`)
        }

        node.primMngr = primMngr
        // console.error(`Adding ${node.name} as child of ${primMngr.name}`) // DEBUG
        primMngr.children.push(node)

        node.possibleMngrNames.forEach(mngrName => {
          const mngr = nodes.find(n => n.name === mngrName)
          if (mngr === undefined) {
            throw new Error(`Invalid org structure. Role '${node.name}' references `
                            + `non-existent possible manager role '${mngrName}'.`)
          }

          node.possibleMngrs.push(mngr)
        })
      }

      const role = roles.get(node.name,
        {
          required  : true,
          errMsgGen : (name) => `Could not find ${node.implied ? 'implied ' : ''}role '${name}' while building org structure.`
        })
      for (const { name: impliedRoleName, mngrProtocol } of role.implies || []) {
        // implied roles are handled by inserting the implied roles as managed by the super-role. When the org chart is
        // generated, these will collapse into a single entry listing multiple roles and using the super role as the
        // title.

        // TODO: this is a little messy
        const impRole = roles.get(impliedRoleName,
          {
            required  : true,
            errMsgGen : (name) => `Could not find implied role '${name}' while building org structure.`
          })
        // console.error(`Processing implied role: ${impRole.name}...`) // DEBUG
        if (impRole.isTitular() && !nodes.find(n => n.name === impRole.name)) { // only titular roles not already defined are implied into the org structure
          // console.error("I'm in!") // DEBUG
          // TODO: in theroy, I believe if the current node has no manager, then implied role's don't either.
          // Otheriwse, the primary manager is effectively one's self, in the 'super' role or the same manager as the
          // super role, depending on the manager protocol.
          // console.error("\n\nHey:\n", role, node, "\n\n")// DEBUG
          const managingRoleName = mngrProtocol === 'self'
            ? role.name
            : mngrProtocol === 'same'
              ? node.primMngrName
              : throw new Error(`Unkown (or undefined?) manager protocol '${mngrProtocol}' found while processing org structure.`)
          // TODO: support optional managers.
          processNode(new Node([impliedRoleName, managingRoleName, null], true))
        }
      }
    }

    for (const node of nodes) {
      processNode(node)
    }

    const orgRoles = this.getNodes().map(n => n.getName())
    // check all org role names reference defined roles
    const undefinedRoles = orgRoles.filter((roleName) => roles.get(roleName) === undefined)
    if (undefinedRoles.length > 0) {
      throw new Error('Found undefined role reference'
                      + `${undefinedRoles.length > 1 ? 's' : ''}: ${undefinedRoles.join(', ')}`)
    }
    // check for duplicate org roles
    const dupeRoles = orgRoles.filter((name, index) => orgRoles.indexOf(name) !== index)
    if (dupeRoles.length > 0) {
      throw new Error(`Found non-unique role${dupeRoles.length > 1 ? 's' : ''} `
                      + `references in org structure: ${dupeRoles.join(', ')}`)
    }
  }

  getRoots() { return [...this.roots] }

  getNodes() {
    return this.roots.reduce((nodes, root) => nodes.concat(root.getTreeNodes()), [])
  }

  getNodeByRoleName(name) {
    return this.getNodes().find(n => n.getName() === name)
  }
}

export { OrgStructure }
