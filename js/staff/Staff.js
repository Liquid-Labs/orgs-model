import { TsvExt } from '../lib'

const Staff = class extends TsvExt {
  static headers = ['Email', 'Family Name', 'Given Name', 'Start Date', 'Primary Roles', 'Secondary Roles', 'Manager']
  static keys = ['email', 'familyName', 'givenName', 'startDate', 'primaryRoles', 'secondaryRoles', 'manager']
  static multis = {'primaryRoles': true, 'secondaryRoles': true}

	constructor(fileName) {
    super(Staff.headers, Staff.keys, fileName, Staff.multis)
	}

  notUnique(data, item) {
    let i
    return -1 !== (i = data.findIndex((line) =>
                                      line[0].toLowerCase() === item.email.toLowerCase()))
           && `Staff member with email '${item.email}' already exists at entry ${i + 1}.`
  }

  matchKey = (line, key) => line[0] === key
}

export { Staff }
