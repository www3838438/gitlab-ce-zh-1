<script>
import Flash from '../../../flash';
import editForm from './edit_form.vue';
import Icon from '../../../vue_shared/components/icon.vue';

export default {
  components: {
    editForm,
    Icon,
  },
  props: {
    isConfidential: {
      required: true,
      type: Boolean,
    },
    isEditable: {
      required: true,
      type: Boolean,
    },
    service: {
      required: true,
      type: Object,
    },
  },
  data() {
    return {
      edit: false,
    };
  },
  computed: {
    confidentialityIcon() {
      return this.isConfidential ? 'eye-slash' : 'eye';
    },
  },
  methods: {
    toggleForm() {
      this.edit = !this.edit;
    },
    updateConfidentialAttribute(confidential) {
      this.service.update('issue', { confidential })
        .then(() => location.reload())
        .catch(() => new Flash('Something went wrong trying to change the confidentiality of this issue'));
    },
  },
};
</script>

<template>
  <div class="block issuable-sidebar-item confidentiality">
    <div class="sidebar-collapsed-icon">
      <icon
        :name="confidentialityIcon"
        :size="16"
        aria-hidden="true">
      </icon>
    </div>
    <div class="title hide-collapsed">
      保密性
      <a
        v-if="isEditable"
        class="pull-right confidential-edit"
        href="#"
        @click.prevent="toggleForm"
      >
        编辑
      </a>
    </div>
    <div class="value sidebar-item-value hide-collapsed">
      <editForm
        v-if="edit"
        :toggle-form="toggleForm"
        :is-confidential="isConfidential"
        :update-confidential-attribute="updateConfidentialAttribute"
      />
      <div v-if="!isConfidential" class="no-value sidebar-item-value">
        <icon
          name="eye"
          :size="16"
          aria-hidden="true"
          class="sidebar-item-icon inline">
        </icon>
        非机密
      </div>
      <div v-else class="value sidebar-item-value hide-collapsed">
        <icon
          name="eye-slash"
          :size="16"
          aria-hidden="true"
          class="sidebar-item-icon inline is-active">
        </icon>
        这是一个保密问题
      </div>
    </div>
  </div>
</template>
