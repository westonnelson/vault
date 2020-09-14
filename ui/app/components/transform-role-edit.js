import TransformBase from './transform-edit-base';

export default TransformBase.extend({
  initialTransformations: null,

  init() {
    this._super(...arguments);
    this.set('initialTransformations', this.get('model.transformations'));
  },

  handleUpdateTransformations(updateTransformations, roleId, type = 'update') {
    if (!updateTransformations) return;
    const backend = this.get('model.backend');
    const promises = updateTransformations.map(transform => {
      return this.store
        .queryRecord('transform', {
          backend,
          id: transform.id,
        })
        .then(function(transformation) {
          let roles = transformation.allowed_roles;
          if (transform.action === 'ADD') {
            roles = this.addToList(roles, roleId);
          } else if (transform.action === 'REMOVE') {
            roles = this.removeFromList(roles, roleId);
          }

          transformation.setProperties({
            backend,
            allowed_roles: roles,
          });

          return transformation.save().catch(e => {
            return { errorStatus: e.httpStatus, ...transform };
          });
        });
    });

    Promise.all(promises).then(res => {
      let hasError = res.find(r => !!r.errorStatus);

      if (hasError) {
        let errorAdding = res.find(r => r.errorStatus === 403 && r.action === 'ADD');
        let errorRemoving = res.find(r => r.errorStatus === 403 && r.action === 'REMOVE');

        let message =
          'The edits to this role were successful, but allowed_roles for its transformations was not edited due to a lack of permissions.';
        if (type === 'create') {
          message =
            'Transformations have been attached to this role, but the role was not added to those transformations’ allowed_roles due to a lack of permissions.';
        } else if (errorAdding && errorRemoving) {
          message =
            'This role was edited to both add and remove transformations; however, this role was not added or removed from those transformations’ allowed_roles due to a lack of permissions.';
        } else if (errorAdding) {
          message =
            'This role was edited to include new transformations, but this role was not added to those transformations’ allowed_roles due to a lack of permissions.';
        } else if (errorRemoving) {
          message =
            'This role was edited to remove transformations, but this role was not removed from those transformations’ allowed_roles due to a lack of permissions.';
        }
        this.get('flashMessages').stickyInfo(message);
      }
    });
  },

  actions: {
    createOrUpdate(type, event) {
      event.preventDefault();

      this.applyChanges('save', () => {
        const roleId = this.get('model.id');
        const newModelTransformations = this.get('model.transformations');

        if (!this.initialTransformations) {
          this.handleUpdateTransformations(
            newModelTransformations.map(t => ({
              id: t,
              action: 'ADD',
            })),
            roleId,
            type
          );
          return;
        }

        const updateTransformations = [...newModelTransformations, ...this.initialTransformations]
          .map(t => {
            if (this.initialTransformations.indexOf(t) < 0) {
              return {
                id: t,
                action: 'ADD',
              };
            }
            if (newModelTransformations.indexOf(t) < 0) {
              return {
                id: t,
                action: 'REMOVE',
              };
            }
            return null;
          })
          .filter(t => !!t);
        this.handleUpdateTransformations(updateTransformations, roleId);
      });
    },
  },
});
