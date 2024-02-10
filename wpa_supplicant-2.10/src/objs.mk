
# 调用编译函数，传入的参数_OBJS_VAR
# 每次调用之前，都对_OBJS_VAR变量重新赋值
#
$(_OBJS_VAR) := $(call BUILDOBJ,$($(_OBJS_VAR)))
# '-'表示出错或执行失败时，不报错，继续运行，不停止
# $(_OBJS_VAR):%.o=%.d将所有的.o文件替换成.d文件
# filter-out,去掉.a文件
-include $(filter-out %.a,$($(_OBJS_VAR):%.o=%.d))
# 获取所有文件的目录
_DIRS += $(dir $($(_OBJS_VAR)))
