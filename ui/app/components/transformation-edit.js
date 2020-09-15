import TransformBase, { addToList, removeFromList } from './transform-edit-base';

export default TransformBase.extend({
  initialRoles: null,

  init() {
    this._super(...arguments);
    this.set('initialRoles', this.get('model.allowed_roles'));
  },

  updateOrCreateRole(role, transformationId, backend) {
    return this.store
      .queryRecord('transform/role', {
        backend,
        id: role.id,
      })
      .then(roleStore => {
        let transformations = roleStore.transformations;
        if (role.action === 'ADD') {
          transformations = addToList(transformations, transformationId);
        } else if (role.action === 'REMOVE') {
          transformations = removeFromList(transformations, transformationId);
        }
        roleStore.setProperties({
          backend,
          transformations,
        });
        console.log(`Saving ${role.id} with transformations`, transformations);
        return roleStore.save().catch(e => {
          return {
            errorStatus: e.httpStatus,
            ...role,
          };
        });
      })
      .catch(e => {
        if (e.httpStatus !== 403 && role.action === 'ADD') {
          // If role doesn't yet exist, create it with this transformation attached
          var newRole = this.store.createRecord('transform/role', {
            id: role.id,
            name: role.id,
            transformations: [transformationId],
            backend,
          });
          return newRole.save().catch(e => {
            return {
              errorStatus: e.httpStatus,
              ...role,
              action: 'CREATE',
            };
          });
        }

        return {
          ...role,
          errorStatus: e.httpStatus,
        };
      });
  },

  handleUpdateRoles(updateRoles, transformationId, type = 'update') {
    if (!updateRoles) return;
    const backend = this.get('model.backend');
    const promises = updateRoles.map(r => this.updateOrCreateRole(r, transformationId, backend));

    Promise.all(promises).then(results => {
      let hasError = results.find(role => !!role.errorStatus);

      if (hasError) {
        let message =
          'The edits to this transformation were successful, but transformations for its roles was not edited due to a lack of permissions.';
        if (results.find(e => !!e.errorStatus && e.errorStatus !== 403)) {
          // if the errors weren't all due to permissions show generic message
          // eg. trying to update a role with empty array as transformations
          message = `You've edited the allowed_roles for this transformation. However, the corresponding edits to some roles' transformations were not made`;
        }
        this.get('flashMessages').stickyInfo(message);
      }
    });
  },

  actions: {
    createOrUpdate(type, event) {
      event.preventDefault();

      this.applyChanges('save', () => {
        const transformationId = this.get('model.id');
        const newModelRoles = this.get('model.allowed_roles') || [];
        const initialRoles = this.get('initialRoles') || [];

        const updateRoles = [...newModelRoles, ...initialRoles]
          .filter(r => r.indexOf('*') < 0) // TODO: expand wildcards into included roles instead
          .map(role => {
            if (initialRoles.indexOf(role) < 0) {
              return {
                id: role,
                action: 'ADD',
              };
            }
            if (newModelRoles.indexOf(role) < 0) {
              return {
                id: role,
                action: 'REMOVE',
              };
            }
            return null;
          })
          .filter(r => !!r);
        this.handleUpdateRoles(updateRoles, transformationId);
      });
    },
  },
});
