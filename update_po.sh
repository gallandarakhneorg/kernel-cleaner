#!/bin/sh

#############################################################
echo "Generating the pot file..."

echo "    [gtk2]"
xgettext -L perl -k_T --from-code=UTF-8 --files-from=po/POTFILES_gtk2.in -o po/template_gtk2.pot || exit 1

echo "    [gtk3]"
xgettext -L perl -k_T --from-code=UTF-8 --files-from=po/POTFILES_gtk3.in -o po/template_gtk3.pot || exit 1

#############################################################
echo "Updating the existing translations..."

echo "    [gtk2]"
for PO_FILE in po/*/LC_MESSAGES/kernel-cleaner-gtk2.po
do
	msgmerge --backup=none -U "$PO_FILE" "po/template_gtk2.pot" || exit 1
done

echo "    [gtk3]"
for PO_FILE in po/*/LC_MESSAGES/kernel-cleaner-gtk3.po
do
	msgmerge --backup=none -U "$PO_FILE" "po/template_gtk3.pot" || exit 1
done

